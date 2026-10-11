package ui

import "base:runtime"
import "core:hash"
import "core:mem"
import "core:fmt"
import "core:c"
import rl "vendor:raylib"

// constants ///////////////////////////////////////////////////////////////////

ID_GENERATOR_BUFFER_SIZE :: #config(UI_ID_GENERATOR_BUFFER_SIZE, 256)
LAYOUT_STACK_SIZE   :: #config(UI_LAYOUT_STACK_SIZE, 32)

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

// globals /////////////////////////////////////////////////////////////////////

global_hot_id              : Id
global_active_id           : Id
global_id_generator_memory : [ID_GENERATOR_BUFFER_SIZE]u8


global_mouse_position  : [2]f32
global_mouse_left_down : bool

global_layout_stack     : [LAYOUT_STACK_SIZE]Layout_Info
global_layout_stack_top : int

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
}

fini :: proc() {
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
    if !global_mouse_left_down {
        global_active_id = 0
    }
    rl.EndDrawing()
}

// utils ///////////////////////////////////////////////////////////////////////

get_id :: proc(loc: runtime.Source_Code_Location, index: int) -> Id {
    index     := index
    line      := loc.line
    raw_path  := raw_data(loc.file_path)
    data      := global_id_generator_memory[:]
    offset    := 0

    mem.copy(raw_data(data[offset:]), &index,   size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &line,    size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), raw_path, min(len(loc.file_path), len(data[offset:])))
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

    // determine state
    if global_active_id == 0 || global_active_id == id {
        if rl.CheckCollisionPointRec(global_mouse_position, rl.Rectangle{x, y, w, h}) {
            global_hot_id = id

            if global_mouse_left_down {
                global_active_id = id
            } else if global_active_id == id {
                clicked = true
                global_active_id = 0
            }
        }
    }

    // draw
    x := x
    y := y
    w := w
    h := h

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
