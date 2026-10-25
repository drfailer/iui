package ui

// Design choice:
// - we don't store component data:
//   @(static) window_data: ui.Window
//   ui.window(&window_data) {}

import "base:runtime"
import "core:hash"
import "core:mem"
import "core:text/edit"
import "core:strings"
import "core:fmt"
import "core:c"
import rl "vendor:raylib"

// constants ///////////////////////////////////////////////////////////////////

LAYOUT_STACK_SIZE    :: #config(UI_LAYOUT_STACK_SIZE,    16)
CONTAINER_STACK_SIZE :: #config(UI_CONTAINER_STACK_SIZE, 16)

EDIT_UNDO_STATE_SCRATCH_CAPACITY :: #config(UI_EDIT_UNDO_STATE_SCRATCH_CAPACITY, 1024)
EDIT_UNDO_TEXT_SCRATCH_CAPACITY  :: #config(UI_EDIT_UNDO_TEXT_SCRATCH_CAPACITY,  1024)

// types ///////////////////////////////////////////////////////////////////////

Id :: #type u32

Padding :: struct { l, r, t, b: f32 }

// TODO: offset and w/h should be merged

Container :: struct {
    x, y, h, w : f32,
    zindex : i32, // TODO
    command_index : i32, // used if we need to modify draw commands (when using a background color)
}

Layout_Mode :: enum { Column, Row }
Layout :: struct {
    mode          : Layout_Mode,
    xoffset       : f32,
    yoffset       : f32,
    x, y, w, h    : f32,
    padding       : Padding,
    item_spacing  : f32,
    item_sizes    : []f32,
    size          : f32, // TODO: we should use a negative size instead of maybe (smaller)
    item_index    : int,
}

Rect :: struct { x, y, w, h, corner_radius: f32, color: rl.Color }
Text :: struct { text: string, x, y: f32, font: rl.Font, font_size: f32, color: rl.Color }
Scissor :: struct { x, y, w, h: f32, begin: bool }
Draw_Command :: union { Rect, Text, Scissor }

Measure_Text_Proc :: #type proc(text: string, font: rl.Font)


// globals /////////////////////////////////////////////////////////////////////

global_hot_id     : Id
global_active_id  : Id
global_focus_flag : bool

global_draw_queue        : [dynamic]Draw_Command
global_measure_text_proc : Measure_Text_Proc

global_mouse_position  : [2]f32
global_mouse_left_down : bool

global_layout_stack    : [dynamic; LAYOUT_STACK_SIZE]Layout
global_container_stack : [dynamic; CONTAINER_STACK_SIZE]Container

global_edit_undo_state_scratch : mem.Scratch
global_edit_undo_text_scratch  : mem.Scratch
global_edit_state              : edit.State

// styles //////////////////////////////////////////////////////////////////////

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
    text_color       = {185, 148, 104, 255},
    color            = {0, 0, 0, 255},
    hover_color      = {46, 46, 46, 255},
    pressed_color    = {0, 0, 0, 255},
    border_color     = {19, 19, 19, 255},
    border_thickness = 1,
    corner_radius    = 0,
}

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
    idle_background_color    = rl.Color{0, 0, 0, 255},
    focused_background_color = rl.Color{10, 10, 10, 255},
    caret_color              = rl.Color{255, 207, 170, 255},
    border_color             = rl.Color{19, 19, 19, 255},
    selection_color          = rl.Color{46, 46, 46, 255},
    text_color               = rl.Color{185, 148, 104, 255},
    selected_text_color      = rl.Color{185, 148, 104, 255},
    padding                  = Padding{2, 2, 2, 2},
}

TEXT_INPUT_CARET_SIZE :: 2

// init / fini /////////////////////////////////////////////////////////////////

UI_Style :: struct {
    font      : rl.Font,
    font_size : f32,
}

style_ui := UI_Style{}

init :: proc() {
    global_hot_id = 0
    global_active_id = 0
    mem.scratch_init(&global_edit_undo_state_scratch, EDIT_UNDO_STATE_SCRATCH_CAPACITY)
    mem.scratch_init(&global_edit_undo_text_scratch, EDIT_UNDO_TEXT_SCRATCH_CAPACITY)
    edit.init(&global_edit_state,
              mem.scratch_allocator(&global_edit_undo_state_scratch),
              mem.scratch_allocator(&global_edit_undo_text_scratch))
    global_draw_queue = make([dynamic]Draw_Command)
}

fini :: proc() {
    delete(global_draw_queue)
    edit.destroy(&global_edit_state)
    mem.scratch_destroy(&global_edit_undo_state_scratch)
    mem.scratch_destroy(&global_edit_undo_text_scratch)
}

init_frame :: proc() {
    global_hot_id = 0

    // reset layout stack
    clear(&global_layout_stack)
    append(&global_layout_stack, Layout{})

    // reset container stack
    clear(&global_container_stack)
    append(&global_container_stack, Container{})

    // get events (things can change within a frame so we collect at the start)
    global_mouse_position = rl.GetMousePosition()
    global_mouse_left_down = rl.IsMouseButtonDown(.LEFT)

    rl.BeginDrawing()
}

fini_frame :: proc() {
    if !global_mouse_left_down && !global_focus_flag {
        global_active_id = 0
    }

    for cmd_variant in global_draw_queue {
        switch cmd in cmd_variant {
        case Rect:
            // TODO: add the border to the options
            if cmd.corner_radius == 0 {
                rl.DrawRectangleRec({cmd.x, cmd.y, cmd.w, cmd.h}, cmd.color)
            } else {
                rl.DrawRectangleRounded({cmd.x, cmd.y, cmd.w, cmd.h}, cmd.corner_radius, 4, cmd.color)
            }
        case Text:
            rl_draw_text_ex(cmd.font, cmd.text, {cmd.x, cmd.y}, cmd.font_size, 0, cmd.color)
        case Scissor:
            if cmd.begin {
                rl.BeginScissorMode(cast(c.int)cmd.x, cast(c.int)cmd.y, cast(c.int)cmd.w, cast(c.int)cmd.h)
            } else {
                rl.EndScissorMode()
            }
        }
    }
    clear(&global_draw_queue)
    rl.EndDrawing()
    free_all(context.temp_allocator)
}

// id & draw ///////////////////////////////////////////////////////////////////

//
// The id is generated using: [user index|8][source line|8][source file path address|8]
//
get_id :: proc(loc: runtime.Source_Code_Location, index: int) -> Id {
    index     := index
    line      := loc.line
    path_addr := raw_data(loc.file_path)
    data, err := mem.alloc_bytes_non_zeroed(2*size_of(int) + size_of(rawptr), 8, context.temp_allocator)
    offset    := 0

    assert(err == nil, "id generator buffer allocation failed")

    mem.copy(raw_data(data[offset:]), &index,   size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &line,    size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &path_addr, size_of(rawptr))
    return hash.fnv32a(data)
}

draw_rect :: proc(x, y, w, h: f32, color: rl.Color, corner_radius: f32 = 0) {
    append(&global_draw_queue, Rect{x, y, w, h, corner_radius, color})
}

draw_text :: proc(text: string, x, y: f32, color: rl.Color, font: Maybe(rl.Font) = nil, font_size: Maybe(f32) = nil) {
    font      := font.?      or_else style_ui.font
    font_size := font_size.? or_else style_ui.font_size
    append(&global_draw_queue, Text{text, x, y, font, font_size, color})
}

measure_text :: proc(text: string, font: Maybe(rl.Font) = nil, font_size: Maybe(f32) = nil) -> [2]f32 {
    font      := font.?      or_else style_ui.font
    font_size := font_size.? or_else style_ui.font_size
    return rl_measure_text(font, text, font_size, 0)
}

begin_scissor_mode :: proc(x, y, w, h: f32) {
    append(&global_draw_queue, Scissor{x, y, w, h, true})
}

end_scissor_mode :: proc() {
    append(&global_draw_queue, Scissor{})
}

// layout ///////////////////////////////////////////////////////////////////////

get_layout :: proc() -> ^Layout {
    return &global_layout_stack[len(global_layout_stack) - 1]
}

get_parent_layout :: proc() -> ^Layout {
    stack_size := len(global_layout_stack)
    if stack_size < 2 do return nil
    return &global_layout_stack[stack_size - 2]
}

//
// Floating layout function allow to push and pop standalone layouts that are
// not integrated in the current layout (ex: start a new layout for a floating
// window).
//

layout_push_floating :: proc(layout: Layout) {
    append(&global_layout_stack, layout)
}

layout_pop_floating :: proc() {
    pop(&global_layout_stack)
}

//
// These functions push and pop layouts in the current window (update the
// offsets of the new layout before push and after pop).
//

layout_push :: proc(layout: Layout) {
    current := get_layout()
    // update the offsets
    layout := layout
    if layout.xoffset == 0 {
        layout.xoffset += current.xoffset
    }
    if layout.yoffset == 0 {
        layout.yoffset += current.yoffset
    }
    layout.x = layout.xoffset
    layout.y = layout.yoffset
    layout.xoffset += layout.padding.l
    layout.yoffset += layout.padding.t
    layout_push_floating(layout)
}

layout_pop :: proc() {
    layout := get_layout()
    w, h := layout.w, layout.h
    if layout.mode == .Column {
        h -= layout.item_spacing
    } else {
        w -= layout.item_spacing
    }
    w += layout.padding.l + layout.padding.r
    h += layout.padding.t + layout.padding.b
    layout_pop_floating()
    layout_update(w, h)
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
// layout items sizes
//

get_layout_item_size :: proc() -> (size: Maybe(f32)) {
    layout := get_layout()
    if layout.item_index < len(layout.item_sizes) {
        size = layout.item_sizes[layout.item_index]
    } else if len(layout.item_sizes) > 0 {
        size = layout.item_sizes[len(layout.item_sizes) - 1]
    }
    if value, ok := size.?; ok && value <= 0 {
        return nil
    }
    return size
}

compute_layout_item_width :: proc(w: f32) -> f32 {
    layout := get_layout()
    if layout.mode == .Column {
        return w if layout.size <= 0 else layout.size
    }
    return get_layout_item_size().? or_else w
}

compute_layout_item_height :: proc(h: f32) -> f32 {
    layout := get_layout()
    if layout.mode == .Row {
        return h if layout.size <= 0 else layout.size
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
// - 0: don't specify a size for this item.
// - If there more items than sizes specified in the slice, the last size value
//   is used for the remaining items.
//

//
// Push column and row layouts (made to be used within an if statement).
//

@(deferred_none=layout_pop)
column :: proc(w: f32 = 0, item_heights := []f32{}, padding: Padding = {}, item_spacing: f32 = 0) -> bool {
    size := w

    // when the size is unspecified, we try to deduce it from the parent
    if size <= 0 {
        parent_layout := get_layout()
        if parent_layout.mode == .Column {
            size = parent_layout.size
        } else {
            size = get_layout_item_size().? or_else 0
        }
    }

    layout_push(Layout{
        mode = .Column,
        item_sizes = item_heights,
        size = size,
        padding = padding,
        item_spacing = item_spacing,
    })
    return true
}

@(deferred_none=layout_pop)
row :: proc(h: f32 = 0, item_widths := []f32{}, padding: Padding = {}, item_spacing: f32 = 0) -> bool {
    size := h

    // when the size is unspecified, we try to deduce it from the parent
    if size <= 0 {
        parent_layout := get_layout()
        if parent_layout.mode == .Row {
            size = parent_layout.size
        } else {
            size = get_layout_item_size().? or_else 0
        }
    }

    layout_push(Layout{
        mode = .Row,
        item_sizes = item_widths,
        size = size,
        padding = padding,
        item_spacing = item_spacing,
    })
    return true
}

//
// When the layout needs to be more complicated than columns and rows, users
// will have to create a box to allocated some space on the screen.
//

box_end :: proc(w, h: f32) {
    end_scissor_mode()
    layout_update(w, h)
}

@(deferred_in=box_end)
box :: proc(w, h: f32) -> bool {
    layout := get_layout()
    begin_scissor_mode(layout.xoffset, layout.yoffset, w, h)
    return true
}

// container ////////////////////////////////////////////////////////////////////

// TODO: just using the stack for containers might not be sufficient (we can't have multiple roots which might be required for floating windows and popups)
// -> perhaps we just need the stack if we have a floating version like for the layouts

get_container :: proc() -> ^Container {
    return &global_container_stack[len(global_container_stack) - 1]
}

// TODO: floating containers

//
// Managed containers.
//

container_push :: proc(container: Container) {
    container := container
    container.command_index = cast(i32)len(global_draw_queue)
    begin_scissor_mode(container.x, container.y, container.w, container.h)
    layout_push(Layout{})
    append(&global_container_stack, container)
}

container_pop :: proc() {
    layout    := get_layout()
    container := get_container()
    cmd       := &global_draw_queue[container.command_index].(Scissor)

    // we update the scissor area with the proper size of the container is
    // resizable (no change on fixed sizes)
    if container.w <= 0 do cmd.w = layout.w
    if container.h <= 0 do cmd.h = layout.h

    pop(&global_container_stack)
    layout_pop()
    end_scissor_mode()
}

// pane ////////////////////////////////////////////////////////////////////////

end_pane :: proc() {
    container := get_container()
    layout    := get_layout()
    cmd       := &global_draw_queue[container.command_index + 1].(Rect)
    cmd.w = layout.w + layout.padding.r
    cmd.h = layout.h + layout.padding.b
    container_pop()
}

@(deferred_none=end_pane)
pane :: proc(bg_color: rl.Color) -> bool {
    container_push({})
    layout := get_layout()
    draw_rect(layout.xoffset, layout.yoffset, 0, 0, bg_color)
    return true
}

// button //////////////////////////////////////////////////////////////////////

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
    draw_rect(x, y, w, h, style_button.border_color)
    x += style_button.border_thickness
    y += style_button.border_thickness
    w -= 2 * style_button.border_thickness
    h -= 2 * style_button.border_thickness

    // inside
    if global_active_id == id {
        draw_rect(x, y, w, h, style_button.pressed_color)
    } else if global_hot_id == id {
        draw_rect(x, y, w, h, style_button.hover_color)
    } else {
        draw_rect(x, y, w, h, style_button.color)
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
    draw_text(label, text_x, text_y, style_button.text_color)

    // return if the button has been clicked
    return clicked
}

button_label :: proc(label: string, w: Maybe(f32) = nil, h: Maybe(f32) = nil, index := 0, loc := #caller_location) -> (clicked: bool) {
    layout := get_layout()
    text_size := measure_text(label)
    padding := style_button.padding
    w := w.? or_else compute_layout_item_width(text_size.x + padding.l + padding.r)
    h := h.? or_else compute_layout_item_height(text_size.y + padding.t + padding.b)
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
    draw_rect(x, y, w, h, style_text_input.border_color)
    x += 1
    y += 1
    w -= 2
    h -= 2

    // background
    if focused {
        draw_rect(x, y, w, h, style_text_input.focused_background_color)
    } else {
        draw_rect(x, y, w, h, style_text_input.idle_background_color)
    }
    x += style_text_input.padding.l
    y += style_text_input.padding.t
    w -= style_text_input.padding.l + style_text_input.padding.r
    h -= style_text_input.padding.t + style_text_input.padding.b

    // text
    content   := strings.to_string(builder^)
    selection := global_edit_state.selection

    // TODO: the text should be centered vertically
    begin_scissor_mode(x, y, w, h)
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

            draw_text(text_before_selection, x, y, style_text_input.selected_text_color)
            x += measure_text(text_before_selection).x

            draw_rect(x, y, selection_size.x, selection_size.y, style_text_input.selection_color)

            draw_text(text_selected, x, y, style_text_input.selected_text_color)
            x += measure_text(text_selected).x

            draw_text(text_after_selection, x, y, style_text_input.text_color)
        } else {
            // TODO: scroll the text relatively to the cursor
            // no selection but focused: draw text and caret
            draw_text(content, x, y, style_text_input.text_color)
            caret_index := clamp(selection[0], 0, len(content))
            text_size := measure_text(content[:caret_index])
            draw_rect(x + text_size.x, y, TEXT_INPUT_CARET_SIZE, style_ui.font_size, style_text_input.caret_color)
        }
    } else {
        // not focused, draw text
        draw_text(content, x, y, style_text_input.text_color)
    }
    end_scissor_mode()
    return
}
