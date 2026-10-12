package ui

import "base:runtime"
import "core:hash"
import "core:mem"
import "core:text/edit"
import "core:strings"
import "core:fmt"
import "core:c"
import rl "vendor:raylib"

// constants ///////////////////////////////////////////////////////////////////

SCRATCH_MEMORY_SIZE :: #config(UI_SCRATCH_MEMORY_SIZE, 1024)
LAYOUT_STACK_SIZE   :: #config(UI_LAYOUT_STACK_SIZE, 32)

EDIT_UNDO_STATE_SCRATCH_CAPACITY :: #config(UI_EDIT_UNDO_STATE_SCRATCH_CAPACITY, 1024)
EDIT_UNDO_TEXT_SCRATCH_CAPACITY:: #config(UI_EDIT_UNDO_TEXT_SCRATCH_CAPACITY, 1024)

// types ///////////////////////////////////////////////////////////////////////

Id :: #type u32

Padding :: struct { l, r, t, b: f32 }

Layout_Mode :: enum { Column, Row }
Layout_Info :: struct {
    mode         : Layout_Mode,
    xoffset      : f32,
    yoffset      : f32,
    h, w         : f32,
    padding      : Padding,
    item_spacing : f32,
    item_sizes   : []f32,
    size         : Maybe(f32),
    item_index   : int,
}

// we have to use draw commands if we want to have different background colors (may also be cleaner)

// globals /////////////////////////////////////////////////////////////////////

global_hot_id     : Id
global_active_id  : Id
global_focus_flag : bool

global_scratch           : mem.Scratch
global_scratch_allocator : mem.Allocator

global_mouse_position  : [2]f32
global_mouse_left_down : bool

global_layout_stack     : [LAYOUT_STACK_SIZE]Layout_Info
global_layout_stack_top : int

global_edit_undo_state_scratch : mem.Scratch
global_edit_undo_text_scratch  : mem.Scratch
global_edit_state              : edit.State

// init / fini /////////////////////////////////////////////////////////////////

UI_Style :: struct {
    font      : rl.Font,
    font_size : f32,
}

style_ui := UI_Style{}

init :: proc() {
    global_hot_id = 0
    global_active_id = 0
    global_layout_stack[0] = Layout_Info{}
    global_layout_stack_top = 1
    mem.scratch_init(&global_scratch, SCRATCH_MEMORY_SIZE)
    global_scratch_allocator = mem.scratch_allocator(&global_scratch)
    mem.scratch_init(&global_edit_undo_state_scratch, EDIT_UNDO_STATE_SCRATCH_CAPACITY)
    mem.scratch_init(&global_edit_undo_text_scratch, EDIT_UNDO_TEXT_SCRATCH_CAPACITY)
    edit.init(&global_edit_state,
              mem.scratch_allocator(&global_edit_undo_state_scratch),
              mem.scratch_allocator(&global_edit_undo_text_scratch))
}

fini :: proc() {
    edit.destroy(&global_edit_state)
    mem.scratch_destroy(&global_edit_undo_state_scratch)
    mem.scratch_destroy(&global_edit_undo_text_scratch)
}

init_frame :: proc() {
    global_hot_id = 0

    // reset layout stack
    global_layout_stack_top = 0

    // get events (things can change within a frame so we collect at the start)
    global_mouse_position = rl.GetMousePosition()
    global_mouse_left_down = rl.IsMouseButtonDown(.LEFT)

    rl.BeginDrawing()
}

fini_frame :: proc() {
    if !global_mouse_left_down && !global_focus_flag {
        global_active_id = 0
    }
    rl.EndDrawing()
}

// utils ///////////////////////////////////////////////////////////////////////

get_id :: proc(loc: runtime.Source_Code_Location, index: int) -> Id {
    index     := index
    line      := loc.line
    raw_path  := raw_data(loc.file_path)
    data, err := mem.alloc_bytes_non_zeroed(2*size_of(int) + len(loc.file_path), 8, global_scratch_allocator)
    offset    := 0

    assert(err == nil, "id generator buffer allocation failed")

    mem.copy(raw_data(data[offset:]), &index,   size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &line,    size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), raw_path, len(loc.file_path))
    return hash.fnv32a(data)
}

draw_text :: proc(text: string, position: rl.Vector2, color: rl.Color, spacing: f32 = 0) -> [2]f32 {
    return rl_draw_text_ex(style_ui.font, text, position, style_ui.font_size, spacing, color)
}

measure_text :: proc(text: string, spacing: f32 = 0) -> [2]f32 {
    return rl_measure_text(style_ui.font, text, style_ui.font_size, spacing)
}

// layout ///////////////////////////////////////////////////////////////////////

//
// Floating layout function allow to push and pop standalone layouts that are
// not integrated in the current layout (ex: start a new layout for a floating
// window).
//

layout_push_floating :: proc(info: Layout_Info) {
    if global_layout_stack_top > len(global_layout_stack) do panic("layout stack overflow")
    global_layout_stack[global_layout_stack_top] = info
    global_layout_stack_top += 1
}

layout_pop_floating :: proc() {
    global_layout_stack_top -= 1
}

//
// These functions push and pop layouts in the current window (update the
// offsets of the new layout before push and after pop).
//

layout_push :: proc(info: Layout_Info) {
    current := get_layout()
    // update the offsets
    info := info
    if info.xoffset == 0 {
        info.xoffset += current.xoffset
    }
    if info.yoffset == 0 {
        info.yoffset += current.yoffset
    }
    layout_push_floating(info)
}

layout_pop :: proc() {
    old_layout := get_layout()
    if old_layout.mode == .Column {
        old_layout.h -= old_layout.item_spacing
    } else {
        old_layout.w -= old_layout.item_spacing
    }
    old_layout.w += old_layout.padding.r
    old_layout.h += old_layout.padding.b
    layout_pop_floating()
    layout_update(old_layout.w, old_layout.h)
}

//
// Helper functions that update the current layout offsets before and after
// drawing a new item.
//

layout_update :: proc(w, h: f32) {
    layout := get_layout()
    if layout.mode == .Column {
        layout.yoffset += h + layout.item_spacing
        layout.h += h + layout.item_spacing
        layout.w = max(layout.w, w)
    } else {
        layout.xoffset += w + layout.item_spacing
        layout.w += w + layout.item_spacing
        layout.h = max(layout.h, h)
    }
    layout.item_index += 1
}

//
// Helpers for interacting with the current layout (get the current layout;
// returns a dummy pointer if no layout), update the style, ...
//

get_layout :: proc() -> ^Layout_Info {
    assert(global_layout_stack_top >= 0)
    if global_layout_stack_top == 0 {
        @(static) dummy_layout: Layout_Info
        dummy_layout = {} // reset to avoid issues
        return &dummy_layout
    }
    return &global_layout_stack[global_layout_stack_top - 1]
}

get_parent_layout :: proc() -> ^Layout_Info {
    if global_layout_stack_top < 2 do return nil
    return &global_layout_stack[global_layout_stack_top - 2]
}

get_layout_item_size :: proc() -> (size: Maybe(f32)) {
    layout := get_layout()
    if layout.item_index < len(layout.item_sizes) {
        size = layout.item_sizes[layout.item_index]
    } else if len(layout.item_sizes) > 0 {
        size = layout.item_sizes[len(layout.item_sizes) - 1]
    }
    if value, ok := size.?; ok && value < 0 {
        return nil
    }
    return size
}

set_layout_padding :: proc(padding: Padding) {
    layout := get_layout()
    layout.padding = padding
    // this function should be called right after a new layout is pushed so we
    // also updated the offsets
    layout.xoffset += padding.l
    layout.yoffset += padding.t
}

set_layout_item_spacing  :: proc(value: f32) {
    get_layout().item_spacing = value
}

compute_layout_item_width :: proc(w: f32) -> f32 {
    layout := get_layout()
    if layout.mode == .Column {
        return layout.size.? or_else w
    }
    return get_layout_item_size().? or_else w
}

compute_layout_item_height :: proc(h: f32) -> f32 {
    layout := get_layout()
    if layout.mode == .Row {
        return layout.size.? or_else h
    }
    return get_layout_item_size().? or_else h
}

//
// Row and Column layout can accept size configurations that works the
// following way:
// - size: the size of the items in the oposit direction (width for column and
//         height for rows)
// - item size: the size of the items in the layout.
//
// The item size can have the folowing value:
// - empty slice (default value): no size is specified.
// - negative item size: don't specify a size for this item.
// - 0 size for an item: don't draw the item.
// - If there more items than sizes specified in the slice, the last size value
//   is used for the remaining items.
//

//
// Push column and row layouts (made to be used within an if statement).
//

@(deferred_out=layout_pop_conditional)
column :: proc(w: Maybe(f32) = nil, item_heights := []f32{}) -> bool {
    size := w

    // when the size is unspecified, we try to deduce it from the parent
    if size == nil {
        parent_layout := get_layout()
        if parent_layout.mode == .Column {
            size = parent_layout.size
        } else {
            size = get_layout_item_size()
        }
    }

    // if the size is 0, return false (we don't draw the content)
    if value, ok := size.?; ok && value == 0 do return false

    layout_push(Layout_Info{
        mode = .Column,
        item_sizes = item_heights,
        size = size,
    })
    return true
}

@(deferred_out=layout_pop_conditional)
row :: proc(h: Maybe(f32) = nil, item_widths := []f32{}) -> bool {
    size := h

    // when the size is unspecified, we try to deduce it from the parent
    if size == nil {
        parent_layout := get_layout()
        if parent_layout.mode == .Row {
            size = parent_layout.size
        } else {
            size = get_layout_item_size()
        }
    }

    // if the size is 0, return false (we don't draw the content)
    if value, ok := size.?; ok && value == 0 do return false

    layout_push(Layout_Info{
        mode = .Row,
        item_sizes = item_widths,
        size = size,
    })
    return true
}

// pop when the layout has been applied
layout_pop_conditional :: proc(pop: bool) {
    if pop do layout_pop()
    layout := get_layout()
    layout.item_index += 1 // make sure the item is advanced
}


//
// When the layout needs to be more complicated than columns and rows, users
// will have to create a box to allocated some space on the screen.
//

box_end :: proc(w, h: f32) {
    rl.EndScissorMode()
    layout_update(w, h)
}

@(deferred_in=box_end)
box :: proc(w, h: f32) -> bool {
    layout := get_layout()
    rl.BeginScissorMode(cast(i32)layout.xoffset, cast(i32)layout.yoffset, cast(i32)w, cast(i32)h)
    return true
}

// pane ////////////////////////////////////////////////////////////////////////

// just allow to change the background and border colors

// button //////////////////////////////////////////////////////////////////////

Button_Style :: struct {
    padding          : Padding,
    text_color       : rl.Color,
    color            : rl.Color,
    hover_color      : rl.Color,
    pressed_color    : rl.Color,
    border_color     : rl.Color,
    border_thickness : f32,
    corner_radius    : f32,
}

style_button := Button_Style{
    padding          = {4, 4, 4, 4},
    text_color       = {255, 255, 255, 255},
    color            = {32, 32, 32, 255},
    hover_color      = {48, 48, 48, 255},
    pressed_color    = {16, 16, 16, 255},
    border_color     = {0, 0, 0, 255},
    border_thickness = 1,
    corner_radius    = 0,
}

button_floating :: proc(label: string, x, y, w, h: f32, index := 0, loc := #caller_location) -> (clicked: bool) {
    id := get_id(loc, index)

    if global_active_id == 0 || global_active_id == id {
        if rl.CheckCollisionPointRec(global_mouse_position, {x, y, w, h}) {
            global_hot_id = id
        }
        if global_mouse_left_down {
            if global_hot_id == id {
                global_active_id  = id
                global_focus_flag = true
            }
        } else if global_active_id == id {
            global_active_id  = 0
            global_focus_flag = false
            if global_hot_id == id {
                clicked = true
            }
        }
    }

    // draw
    x, y, w, h := x, y, w, h

    // border
    rl.DrawRectangleRec(rl.Rectangle{x, y, w, h}, style_button.border_color)
    x += style_button.border_thickness
    y += style_button.border_thickness
    w -= 2 * style_button.border_thickness
    h -= 2 * style_button.border_thickness

    // inside
    if global_active_id == id {
        rl.DrawRectangleRec(rl.Rectangle{x, y, w, h}, style_button.pressed_color)
    } else if global_hot_id == id {
        rl.DrawRectangleRec(rl.Rectangle{x, y, w, h}, style_button.hover_color)
    } else {
        rl.DrawRectangleRec(rl.Rectangle{x, y, w, h}, style_button.color)
    }
    x += style_button.padding.l
    y += style_button.padding.t
    w -= style_button.padding.l + style_button.padding.r
    h -= style_button.padding.t + style_button.padding.b

    // text
    text_size := measure_text(label)
    padding := style_button.padding
    text_x := x + (w - text_size.x) / 2
    text_y := y + (h - text_size.y) / 2
    draw_text(label, {text_x, text_y}, style_button.text_color)

    // return if the button has been clicked
    return clicked
}

button_label :: proc(label: string, index := 0, loc := #caller_location) -> (clicked: bool) {
    layout := get_layout()
    text_size := measure_text(label)
    padding := style_button.padding
    w := compute_layout_item_width(text_size.x + padding.l + padding.r)
    h := compute_layout_item_height(text_size.y + padding.t + padding.b)
    if w > 0 && h > 0 {
        clicked = button_floating(label, layout.xoffset, layout.yoffset, w, h, index, loc)
    }
    layout_update(w, h)
    return clicked
}

// TODO: button_icon (not sure how to handle icon pack yet)

button :: proc{
    button_label
}

// checkbox ////////////////////////////////////////////////////////////////////

// slider //////////////////////////////////////////////////////////////////////

// header //////////////////////////////////////////////////////////////////////

// text input //////////////////////////////////////////////////////////////////

TEXT_INPUT_CARET_SIZE :: 2

Text_Input_Style :: struct {
    idle_background_color : rl.Color,
    focused_background_color : rl.Color,
    caret_color : rl.Color,
    border_color : rl.Color,
    selection_color : rl.Color,
    text_color : rl.Color,
    selected_text_color : rl.Color,
    padding : Padding,
}

style_text_input := Text_Input_Style{
    idle_background_color    = rl.Color{48, 48, 48, 255},
    focused_background_color = rl.Color{32, 32, 32, 255},
    caret_color              = rl.Color{255, 255, 255, 255},
    border_color             = rl.Color{0, 0, 0, 255},
    selection_color          = rl.Color{100, 100, 100, 255},
    text_color               = rl.Color{255, 255, 255, 255},
    selected_text_color      = rl.Color{255, 255, 255, 255},
    padding                  = Padding{2, 2, 2, 2},
}

text_input_floating :: proc(builder: ^strings.Builder, x, y, w, h: f32, index := 0, loc := #caller_location) -> (submitted: bool) {
    @(static) scroll_xoffset : f32 = 0 // used to scroll the text when it goes out of the box
    id := get_id(loc, index)
    focused: bool

    // determine state
    if global_active_id == 0 || global_active_id == id {
        if rl.CheckCollisionPointRec(global_mouse_position, rl.Rectangle{x, y, w, h}) {
            global_hot_id = id
        }
        if global_mouse_left_down {
            if global_hot_id == id {
                // take or keep focus if hovered and clicked
                global_active_id  = id
                global_focus_flag = true
                scroll_xoffset = 0
                edit.begin(&global_edit_state, cast(u64)id, builder)
            } else if global_active_id == id {
                // lose focus if click happens outside of the edit box
                global_focus_flag = false
                scroll_xoffset = 0
                defer edit.end(&global_edit_state)
            }
        }
    }
    focused = global_active_id == id

    // get inputs
    // NOTE: since the edit state holds the id (which is non 0 when the text
    //       box is focused), we could technically move this elsewhere (to
    //       group event handling)
    if focused {
        command: edit.Command
        shift  := rl.IsKeyDown(.LEFT_SHIFT)

        if rl.IsKeyDown(.LEFT_CONTROL) {
            switch {
            case rl.IsKeyPressed(.LEFT)     : command = .Select_Word_Left  if shift else .Word_Left
            case rl.IsKeyPressed(.RIGHT)    : command = .Select_Word_Right if shift else .Word_Right
            case rl.IsKeyPressed(.BACKSPACE): command = .Delete_Word_Left
            case rl.IsKeyPressed(.DELETE)   : command = .Delete_Word_Right
            case rl.IsKeyPressed(.A)        : global_edit_state.selection = {0, len(builder.buf[:])}
            case rl.IsKeyPressed(.V)        : fmt.println("TODO: paste")
            case rl.IsKeyPressed(.Z)        : command = .Undo
            case rl.IsKeyPressed(.Y)        : command = .Redo
            case rl.IsKeyPressed(.C) && edit.has_selection(&global_edit_state): fmt.println("TODO: copy")
            }
        } else {
            // TODO: we need to handle the mouse as well
            switch {
            case rl.IsKeyPressed(.LEFT)     : command = .Select_Left       if shift else .Left
            case rl.IsKeyPressed(.RIGHT)    : command = .Select_Right      if shift else .Right
            case rl.IsKeyPressed(.HOME)     : command = .Select_Start if shift else .Start
            case rl.IsKeyPressed(.END)      : command = .Select_End   if shift else .End
            case rl.IsKeyPressed(.BACKSPACE): command = .Backspace
            case rl.IsKeyPressed(.DELETE)   : command = .Delete
            case rl.IsKeyPressed(.ENTER):
                submitted = true
                global_active_id  = 0
                global_focus_flag = false
                scroll_xoffset = 0
            case:
                // TODO: it would be more efficient to collect the keys first before inserting
                for {
                    c := rl.GetCharPressed()
                    if c == 0 do break
                    edit.input_rune(&global_edit_state, c)
                }
            }
        }
        edit.perform_command(&global_edit_state, command)
    }

    // draw
    x, y, w, h := x, y, w, h

    // border
    rl.DrawRectangleRec({x, y, w, h}, style_text_input.border_color)
    x += 1
    y += 1
    w -= 2
    h -= 2

    // background
    if focused {
        rl.DrawRectangleRec({x, y, w, h}, style_text_input.focused_background_color)
    } else {
        rl.DrawRectangleRec({x, y, w, h}, style_text_input.idle_background_color)
    }
    x += style_text_input.padding.l
    y += style_text_input.padding.t
    w -= style_text_input.padding.l + style_text_input.padding.r
    h -= style_text_input.padding.t + style_text_input.padding.b

    // text
    content   := strings.to_string(builder^)
    selection := global_edit_state.selection

    // TODO: the text should be centered vertically
    rl.BeginScissorMode(cast(i32)x, cast(i32)y, cast(i32)w, cast(i32)h)
    if focused {

        // update the scroll offset
        {
            text_before_caret_size := measure_text(content[:selection[0]])
            caret_pos := text_before_caret_size.x + scroll_xoffset
            if caret_pos < 0 {
                scroll_xoffset = -text_before_caret_size.x
            } else if caret_pos > (w - TEXT_INPUT_CARET_SIZE) {
                scroll_xoffset = (w - TEXT_INPUT_CARET_SIZE) - text_before_caret_size.x
            }
            x += scroll_xoffset
        }

        if edit.has_selection(&global_edit_state) {
            sb := selection[0] // selection begin
            se := selection[1] // selection end
            if sb > se do sb, se = se, sb

            text_before_selection := string(content[:sb])
            text_selected         := string(content[sb:se])
            text_after_selection  := string(content[se:])
            selection_size        := measure_text(text_selected)

            x += draw_text(text_before_selection, {x, y}, style_text_input.selected_text_color).x
            rl.DrawRectangleRec({x, y, selection_size.x, selection_size.y}, style_text_input.selection_color)
            x += draw_text(text_selected, {x, y}, style_text_input.selected_text_color).x
            x += draw_text(text_after_selection, {x, y}, style_text_input.text_color).x
        } else {
            // TODO: scroll the text relatively to the cursor
            // no selection but focused: draw text and caret
            draw_text(content, {x, y}, style_text_input.text_color)
            caret_index := clamp(selection[0], 0, len(content))
            text_size := measure_text(content[:caret_index])
            rl.DrawRectangleRec({x + text_size.x, y, TEXT_INPUT_CARET_SIZE, style_ui.font_size}, style_text_input.caret_color)
        }
    } else {
        // not focused, draw text
        draw_text(content, {x, y}, style_text_input.text_color)
    }
    rl.EndScissorMode()
    return
}
