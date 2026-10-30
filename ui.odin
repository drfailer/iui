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

// TODO: z indexing support
// TODO: pane border
// TODO: scrollbox
// TODO: header title external padding (outside of the rectangle)
// TODO: style should be an argument

// constants ///////////////////////////////////////////////////////////////////

LAYOUT_STACK_SIZE    :: #config(UI_LAYOUT_STACK_SIZE,    16)
CONTAINER_STACK_SIZE :: #config(UI_CONTAINER_STACK_SIZE, 16)
ID_STACK_SIZE        :: #config(UI_ID_STACK_SIZE, 32)

EDIT_UNDO_STATE_SCRATCH_CAPACITY :: #config(UI_EDIT_UNDO_STATE_SCRATCH_CAPACITY, 1024)
EDIT_UNDO_TEXT_SCRATCH_CAPACITY  :: #config(UI_EDIT_UNDO_TEXT_SCRATCH_CAPACITY,  1024)

// types ///////////////////////////////////////////////////////////////////////

Id :: #type u32

Rect :: struct { x, y, w, h: f32 }

Padding :: struct { l, r, t, b: f32 }
Border_Data :: struct($T: typeid) { l, r, t, b: T }

Container_Opt :: enum { Resizable, Moveable }
Container_Opts :: bit_set[Container_Opt]

Container :: struct {
    x, y, w, h    : f32,
    zindex        : u8,
    command_index : i32, // used if we need to modify draw commands (when using a background color)
    scrolloffset  : [2]f32,
    opts          : Container_Opts,
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
    size          : f32,
    item_index    : int,
}

Measure_Text_Proc :: #type proc(text: string, font: rl.Font)

// draw queue //////////////////////////////////////////////////////////////////

Command_Rect :: struct { x, y, w, h, corner_radius: f32, color: rl.Color }
Command_Text :: struct { text: string, x, y: f32, font: rl.Font, font_size: f32, color: rl.Color }
Command_Clip :: struct { x, y, w, h: f32, begin: bool }
Draw_Command :: union { Command_Rect, Command_Text, Command_Clip }

Draw_Queue :: struct {
    zqueues   : [256][dynamic]Draw_Command,
    max_index : u8,
    allocator : mem.Allocator,
}

draw_queue_init :: proc(queue: ^Draw_Queue, allocator := context.allocator) {
    queue.allocator = allocator
    queue.zqueues[0] = make([dynamic]Draw_Command, allocator = allocator)
}

draw_queue_destroy :: proc(queue: ^Draw_Queue) {
    for &queue in queue.zqueues {
        delete(queue)
    }
}

draw_queue_push :: proc(queue: ^Draw_Queue, zindex: u8, command: Draw_Command) {
    append(&queue.zqueues[zindex], command)
    queue.max_index = max(queue.max_index, zindex)
}

// globals /////////////////////////////////////////////////////////////////////

global_hot_id     : Id
global_active_id  : Id
global_focus_flag : bool

global_draw_queue        : Draw_Queue
global_measure_text_proc : Measure_Text_Proc

global_mouse_position  : [2]f32
global_mouse_left_down : bool

global_layout_stack    : [dynamic; LAYOUT_STACK_SIZE]Layout
global_container_stack : [dynamic; CONTAINER_STACK_SIZE]^Container
global_id_stack        : [dynamic; ID_STACK_SIZE]int

global_container_map   : map[Id]^Container // TODO: find a way to avoid double hashing
global_container_arena : mem.Dynamic_Arena

global_edit_undo_state_scratch : mem.Scratch
global_edit_undo_text_scratch  : mem.Scratch
global_edit_state              : edit.State

// styles //////////////////////////////////////////////////////////////////////

// UI //////////////////////////////////

UI_Style :: struct {
    font       : rl.Font,
    font_size  : f32,
    text_color : rl.Color,
}

style_ui := UI_Style{
    text_color = {185, 148, 104, 255},
}

// Button //////////////////////////////

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

// Checkbox ////////////////////////////

Checkbox_Style :: struct {
    box_color   : rl.Color,
    label_color : rl.Color,
}

style_checkbox := Checkbox_Style{
    box_color   = {185, 148, 104, 255},
    label_color = {185, 148, 104, 255},
}

CHECKBOX_BORDER_SIZE   :: 1
CHECKBOX_LABEL_SPACING :: 4

// Slider //////////////////////////////

Slider_Style :: struct {
    thumb_height     : f32,
    thumb_width      : f32,
    thumb_radius     : f32,
    bar_height       : f32,
    border_thickness : f32,
    thumb_color      : rl.Color,
    bar_color        : rl.Color,
    border_color     : rl.Color,
}

style_slider := Slider_Style{
    thumb_height     = 16,
    thumb_width      = 4,
    thumb_radius     = 0,
    bar_height       = 16,
    border_thickness = 1,
    thumb_color      = {185, 148, 104, 255},
    bar_color        = {0, 0, 0, 255},
    border_color     = {19, 19, 19, 255},
}

DEFAULT_SLIDER_WIDTH :: 60

// Header //////////////////////////////

Header_Level_Style :: struct {
    padding          : Padding,
    text_color       : rl.Color,
    color            : rl.Color,
    hover_color      : rl.Color,
    pressed_color    : rl.Color,
    border_color     : rl.Color,
    border_thickness : f32,
    openned_symbol   : string,
    closed_symbol    : string,
}

Header_Style :: [3]Header_Level_Style

style_header := Header_Style{
    {
        padding          = {4, 4, 4, 4},
        text_color       = {185, 148, 104, 255},
        color            = {64, 64, 64, 255},
        hover_color      = {46, 46, 46, 255},
        pressed_color    = {0, 0, 0, 255},
        border_color     = {19, 19, 19, 255},
        border_thickness = 1,
        openned_symbol   = "v",
        closed_symbol    = ">",
    },
    {
        padding          = {4, 4, 4, 4},
        text_color       = {185, 148, 104, 255},
        color            = {64, 64, 64, 255},
        hover_color      = {46, 46, 46, 255},
        pressed_color    = {0, 0, 0, 255},
        border_color     = {19, 19, 19, 255},
        border_thickness = 1,
        openned_symbol   = "-",
        closed_symbol    = "+",
    },
    {
        padding          = {4, 4, 4, 4},
        text_color       = {185, 148, 104, 255},
        color            = {64, 64, 64, 255},
        hover_color      = {46, 46, 46, 255},
        pressed_color    = {0, 0, 0, 255},
        border_color     = {19, 19, 19, 255},
        border_thickness = 1,
        openned_symbol   = "-",
        closed_symbol    = "+",
    },
}
HEADER_SYMBOL_SPACING :: 20

// Command_Text Input //////////////////////////

Text_Input_Style :: struct {
    idle_background_color    : rl.Color,
    focused_background_color : rl.Color,
    caret_color              : rl.Color,
    border_color             : rl.Color,
    selection_color          : rl.Color,
    text_color               : rl.Color,
    selected_text_color      : rl.Color,
    padding                  : Padding,
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

init :: proc() {
    global_hot_id = 0
    global_active_id = 0
    mem.scratch_init(&global_edit_undo_state_scratch, EDIT_UNDO_STATE_SCRATCH_CAPACITY)
    mem.scratch_init(&global_edit_undo_text_scratch, EDIT_UNDO_TEXT_SCRATCH_CAPACITY)
    edit.init(&global_edit_state,
              mem.scratch_allocator(&global_edit_undo_state_scratch),
              mem.scratch_allocator(&global_edit_undo_text_scratch))
    draw_queue_init(&global_draw_queue)
    mem.dynamic_arena_init(&global_container_arena)
    global_container_map = make(map[Id]^Container)
}

fini :: proc() {
    draw_queue_destroy(&global_draw_queue)
    edit.destroy(&global_edit_state)
    mem.scratch_destroy(&global_edit_undo_state_scratch)
    mem.scratch_destroy(&global_edit_undo_text_scratch)
    mem.dynamic_arena_destroy(&global_container_arena)
    delete(global_container_map)
}

init_frame :: proc(screen_w, screen_h: f32) {
    global_hot_id = 0

    // reset container stack
    clear(&global_layout_stack)
    clear(&global_container_stack)
    container_push_floating(0, 0, screen_w, screen_h, 0, {})

    // get events (things can change within a frame so we collect at the start)
    global_mouse_position = rl.GetMousePosition()
    global_mouse_left_down = rl.IsMouseButtonDown(.LEFT)

    rl.BeginDrawing()
}

fini_frame :: proc() {
    if !global_mouse_left_down && !global_focus_flag {
        global_active_id = 0
    }

    for &zqueue in global_draw_queue.zqueues[:global_draw_queue.max_index + 1] {
        for cmd_variant in zqueue {
            switch cmd in cmd_variant {
            case Command_Rect:
                // TODO: add the border to the options
                if cmd.corner_radius == 0 {
                    rl.DrawRectangleRec({cmd.x, cmd.y, cmd.w, cmd.h}, cmd.color)
                } else {
                    rl.DrawRectangleRounded({cmd.x, cmd.y, cmd.w, cmd.h}, cmd.corner_radius, 4, cmd.color)
                }
            case Command_Text:
                rl_draw_text_ex(cmd.font, cmd.text, {cmd.x, cmd.y}, cmd.font_size, 0, cmd.color)
            case Command_Clip:
                if cmd.begin {
                    rl.BeginScissorMode(cast(c.int)cmd.x, cast(c.int)cmd.y, cast(c.int)cmd.w, cast(c.int)cmd.h)
                } else {
                    rl.EndScissorMode()
                }
            }
        }
        clear(&zqueue)
    }
    rl.EndDrawing()
    free_all(context.temp_allocator)
}

// id & draw ///////////////////////////////////////////////////////////////////

push_id :: proc(id: int) {
    append(&global_id_stack, id)
}

pop_id :: proc(id: int) {
    pop(&global_id_stack)
}

id_stack_top :: proc() -> int {
    if len(global_id_stack) == 0 do return 0
    return global_id_stack[len(global_id_stack) - 1]
}

//
// The id is generated using: [id stack top|8][source line|8][source file path address|8]
//
get_id :: proc(loc: runtime.Source_Code_Location) -> Id {
    pushed_id := id_stack_top()
    line      := loc.line
    path_addr := raw_data(loc.file_path)
    data, err := mem.alloc_bytes_non_zeroed(2*size_of(int) + size_of(rawptr), 8, context.temp_allocator)
    offset    := 0

    assert(err == nil, "id generator buffer allocation failed")

    mem.copy(raw_data(data[offset:]), &pushed_id,   size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &line,    size_of(int))
    offset += size_of(int)
    mem.copy(raw_data(data[offset:]), &path_addr, size_of(rawptr))
    return hash.fnv32a(data)
}

draw_rect :: proc(x, y, w, h: f32, color: rl.Color, corner_radius: f32 = 0, zindex: u8 = get_container().zindex) {
    draw_queue_push(&global_draw_queue, zindex, Command_Rect{x, y, w, h, corner_radius, color})
}

draw_text :: proc(text: string, x, y: f32, color: rl.Color, font: Maybe(rl.Font) = nil, font_size: Maybe(f32) = nil, zindex: u8 = get_container().zindex) {
    font      := font.?      or_else style_ui.font
    font_size := font_size.? or_else style_ui.font_size
    draw_queue_push(&global_draw_queue, zindex, Command_Text{text, x, y, font, font_size, color})
}

measure_text :: proc(text: string, font: Maybe(rl.Font) = nil, font_size: Maybe(f32) = nil) -> [2]f32 {
    font      := font.?      or_else style_ui.font
    font_size := font_size.? or_else style_ui.font_size
    return rl_measure_text(font, text, font_size, 0)
}

begin_clip :: proc(x, y, w, h: f32, zindex: u8 = get_container().zindex) {
    draw_queue_push(&global_draw_queue, zindex, Command_Clip{x, y, w, h, true})
}

end_clip :: proc(zindex: u8 = get_container().zindex) {
    draw_queue_push(&global_draw_queue, zindex, Command_Clip{})
}

draw_base :: proc(x, y, w, h: f32, border_thickness, corner_radius: f32, color, border_color: rl.Color, padding: Padding) -> (nx, ny, nw, nh: f32) {
    nx, ny, nw, nh = x, y, w, h

    // border
    draw_rect(nx, ny, nw, nh, border_color, corner_radius)
    nx += border_thickness
    ny += border_thickness
    nw -= 2*border_thickness
    nh -= 2*border_thickness

    // background
    draw_rect(nx, ny, nw, nh, color, corner_radius)
    nx += padding.l
    ny += padding.t
    nw -= padding.l + padding.r
    nh -= padding.t + padding.b
    return
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

layout_push_floating :: proc(
    mode: Layout_Mode,
    x, y: f32,
    padding      := Padding{},
    item_spacing := f32(0),
    item_sizes   := []f32{},
    size         := f32(0),
) {
    append(&global_layout_stack, {
        mode         = mode,
        xoffset      = x + padding.l,
        yoffset      = y + padding.t,
        x            = x,
        y            = y,
        padding      = padding,
        item_spacing = item_spacing,
        item_sizes   = item_sizes,
        size         = size,
    })
}

layout_pop_floating :: proc() -> (w, h: f32) {
    layout := get_layout()
    w, h = layout.w, layout.h
    if layout.mode == .Column {
        h -= layout.item_spacing
    } else {
        w -= layout.item_spacing
    }
    w += layout.padding.l + layout.padding.r
    h += layout.padding.t + layout.padding.b
    pop(&global_layout_stack)
    return
}

//
// These functions push and pop layouts in the current window (update the
// offsets of the new layout before push and after pop).
//

layout_push :: proc(
    mode: Layout_Mode,
    padding      := Padding{},
    item_spacing := f32(0),
    item_sizes   := []f32{},
    size         := f32(0),
) {
    current := get_layout()
    layout_push_floating(mode, current.xoffset, current.yoffset, padding, item_spacing, item_sizes, size)
}

layout_pop :: proc() {
    w, h := layout_pop_floating()
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
    layout_push(.Column, item_sizes = item_heights, size = size, padding = padding, item_spacing = item_spacing)
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

    layout_push(.Row, item_sizes = item_widths, size = size, padding = padding, item_spacing = item_spacing)
    return true
}

//
// When the layout needs to be more complicated than columns and rows, users
// will have to create a box to allocated some space on the screen.
//

box_end :: proc(w, h: f32) {
    end_clip()
    layout_update(w, h)
}

@(deferred_in=box_end)
box :: proc(w, h: f32) -> bool {
    layout := get_layout()
    begin_clip(layout.xoffset, layout.yoffset, w, h)
    return true
}

// container ////////////////////////////////////////////////////////////////////

get_current_container :: proc() -> ^Container {
    return global_container_stack[len(global_container_stack) - 1]
}

get_container_from_id :: proc(id: Id) -> ^Container {
    if container, ok := global_container_map[id]; ok {
        return container
    }
    container := new(Container, mem.dynamic_arena_allocator(&global_container_arena))
    global_container_map[id] = container
    return container
}

get_container :: proc{get_current_container, get_container_from_id}

container_push_floating :: proc(x, y, w, h: f32, id: Id, zindex := u8(0), padding := Padding{}) {
    container := get_container(id)

    if .Moveable not_in container.opts {
        container.x = x
        container.y = y
        container.zindex = zindex
    }
    if .Resizable not_in container.opts {
        container.w = w
        container.h = h
    }
    container.command_index = cast(i32)len(global_draw_queue.zqueues[zindex])

    layout_push_floating(.Column, x, y, padding = padding)
    append(&global_container_stack, container)
    begin_clip(x, y, w, h)
}

container_pop_floating :: proc() -> (w, h: f32) {
    w, h = layout_pop_floating()

    container := get_container()
    cmd       := &global_draw_queue.zqueues[container.zindex][container.command_index].(Command_Clip)

    // we update the scissor area with the proper size of the container is
    // resizable (no change on fixed sizes)
    if container.w <= 0 do cmd.w = w
    if container.h <= 0 do cmd.h = h

    pop(&global_container_stack)
    end_clip()
    return
}

container_push :: proc(id: Id, padding := Padding{}) {
    layout := get_layout()
    container_push_floating(layout.xoffset, layout.yoffset, 0, 0, id, 0, padding)
}

container_pop :: proc() {
    w, h := container_pop_floating()
    layout_update(w, h)
}

// pane ////////////////////////////////////////////////////////////////////////

//
// The pane is purely a style component that allow to change the background
// color behind other components (it doesn't support any interaction).
//

pane_end :: proc() {
    container := get_container()
    layout    := get_layout()
    w, h      := layout.w + layout.padding.l + layout.padding.r, layout.h + layout.padding.t + layout.padding.b

    // background
    cmd_bg := &global_draw_queue.zqueues[container.zindex][container.command_index + 1].(Command_Rect)
    cmd_bg.w = w
    cmd_bg.h = h

    // left border
    cmd_b_l := &global_draw_queue.zqueues[container.zindex][container.command_index + 2].(Command_Rect)
    cmd_b_l.h = h

    // right border
    cmd_b_r := &global_draw_queue.zqueues[container.zindex][container.command_index + 3].(Command_Rect)
    cmd_b_r.h = h
    layout.xoffset += cmd_b_r.w
    layout.w += cmd_b_r.w

    // top border
    cmd_b_t := &global_draw_queue.zqueues[container.zindex][container.command_index + 4].(Command_Rect)
    cmd_b_t.w = w

    // bottom border
    cmd_b_b := &global_draw_queue.zqueues[container.zindex][container.command_index + 5].(Command_Rect)
    cmd_b_b.w = w
    layout.yoffset += cmd_b_r.h
    layout.h += cmd_b_r.h

    container_pop()
}

// TODO: this could be resizable?

@(deferred_none=pane_end)
pane :: proc(
    bg_color        : rl.Color = {},
    border_color    : Border_Data(rl.Color) = {},
    border_thickness: Border_Data(f32) = {},
    padding         : Padding = {},
    loc := #caller_location,
) -> bool {
    id := get_id(loc)

    container_push(id, padding)
    layout := get_layout()

    //background
    draw_rect(layout.x, layout.y, 0, 0, bg_color)

    draw_rect(layout.x, layout.y, border_thickness.l, 0, border_color.l)
    draw_rect(layout.x, layout.y, border_thickness.r, 0, border_color.r)
    draw_rect(layout.x, layout.y, 0, border_thickness.t, border_color.t)
    draw_rect(layout.x, layout.y, 0, border_thickness.b, border_color.b)

    layout.w += border_thickness.l
    layout.h += border_thickness.t
    layout.xoffset += border_thickness.l
    layout.yoffset += border_thickness.t
    return true
}

// tabs ////////////////////////////////////////////////////////////////////////

// TODO

// window //////////////////////////////////////////////////////////////////////

// TODO: popup and dragable windows?

// component utility functions /////////////////////////////////////////////////

point_in_region :: proc(x, y: f32, clip: Rect) -> bool {
    xb := clip.x
    xe := clip.x + clip.w
    yb := clip.y
    ye := clip.y + clip.h
    return (xb <= x && x < xe) && (yb <= y && y < ye)
}

//
// Logic for clickable components
//
is_component_clicked :: proc(id: Id, x, y, w, h: f32) -> (clicked: bool) {
    if global_active_id == 0 || global_active_id == id {
        if point_in_region(global_mouse_position.x, global_mouse_position.y, {x, y, w, h}) {
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
    return
}

// text ////////////////////////////////////////////////////////////////////////

text_floating :: proc(x, y, w, h: f32, content: string, color := style_ui.text_color, loc := #caller_location) {
    begin_clip(x, y, w, h)
    draw_text(content, x, y, color)
    end_clip()
}

text :: proc(content: string, color := style_ui.text_color, loc := #caller_location) {
    layout := get_layout()
    text_size := measure_text(content)
    text_floating(layout.xoffset, layout.yoffset, text_size.x, text_size.y, content, color, loc)
    layout_update(text_size.x, text_size.y)
}

textf :: proc(f: string, data: ..any, color := style_ui.text_color, loc := #caller_location) {
    content := fmt.aprintf(f, ..data, allocator = context.temp_allocator)
    text(content, color, loc)
}

// image ///////////////////////////////////////////////////////////////////////

// TODO

// button //////////////////////////////////////////////////////////////////////

button_floating :: proc(x, y, w, h: f32, label: string, style := style_button, loc := #caller_location) -> (clicked: bool) {
    id := get_id(loc)

    clicked = is_component_clicked(id, x, y, w, h)
    color := style.color
    if global_active_id == id do color = style.pressed_color
    else if global_hot_id == id do color = style.hover_color

    // draw
    x, y, w, h := draw_base(x, y, w, h, style.border_thickness, style.corner_radius, color, style.border_color, style.padding)

    // text
    text_size := measure_text(label)
    text_x := x + (w - text_size.x) / 2
    text_y := y + (h - text_size.y) / 2
    draw_text(label, text_x, text_y, style.text_color)

    // return if the button has been clicked
    return clicked
}

button_label :: proc(label: string, w: Maybe(f32) = nil, h: Maybe(f32) = nil, style := style_button, loc := #caller_location) -> (clicked: bool) {
    layout := get_layout()
    text_size := measure_text(label)
    padding := style.padding
    w := w.? or_else compute_layout_item_width(text_size.x + padding.l + padding.r)
    h := h.? or_else compute_layout_item_height(text_size.y + padding.t + padding.b)
    if w > 0 && h > 0 {
        clicked = button_floating(layout.xoffset, layout.yoffset, w, h, label, style, loc)
    }
    layout_update(w, h)
    return clicked
}

// TODO: button_icon (not sure how to handle icon pack yet)

button :: proc{
    button_label
}

// checkbox ////////////////////////////////////////////////////////////////////

checkbox_floating :: proc(x, y, w, h: f32, label: string, checked: ^bool, style := style_checkbox, loc := #caller_location) -> (clicked: bool) {
    id       := get_id(loc)
    box_size := style_ui.font_size

    clicked = is_component_clicked(id, x, y, box_size, box_size)

    if clicked {
        checked^ = !(checked^)
    }

    draw_rect(x,                                   y,                                   box_size,             CHECKBOX_BORDER_SIZE, style.box_color)
    draw_rect(x,                                   y,                                   CHECKBOX_BORDER_SIZE, box_size,             style.box_color)
    draw_rect(x,                                   y + box_size - CHECKBOX_BORDER_SIZE, box_size,             CHECKBOX_BORDER_SIZE, style.box_color)
    draw_rect(x + box_size - CHECKBOX_BORDER_SIZE, y,                                   CHECKBOX_BORDER_SIZE, box_size,             style.box_color)
    if checked^ {
        draw_rect(x + 4, y + 4, box_size - 8, box_size - 8, style.box_color)
    }
    draw_text(label, x + box_size + CHECKBOX_LABEL_SPACING, y, style.label_color)

    return clicked
}

checkbox :: proc(label: string, checked: ^bool, style := style_checkbox, loc := #caller_location) -> (clicked: bool) {
    layout    := get_layout()
    text_size := measure_text(label)
    assert(text_size.y == style_ui.font_size)
    w := style_ui.font_size + CHECKBOX_LABEL_SPACING + text_size.x
    h := style_ui.font_size
    clicked = checkbox_floating(layout.xoffset, layout.yoffset, w, h, label, checked, style, loc)
    layout_update(w, h)
    return clicked
}

// slider //////////////////////////////////////////////////////////////////////

slider_floating :: proc(x, y, w, h: f32, lower_bound, upper_bound: $T, value: ^T, style := style_slider, loc := #caller_location) -> (updated: bool) {
    id := get_id(loc)
    value_range := cast(f32)(upper_bound - lower_bound)

    if global_active_id == 0 || global_active_id == id {
        if rl.CheckCollisionPointRec(global_mouse_position, {x, y, w, h}) {
            global_hot_id = id
            if global_mouse_left_down {
                global_active_id = id
            }
        }
    }

    // bar + border
    bw := w
    bh := style.bar_height + 2*style.border_thickness
    bx := x
    by := y + (h - bh)/2

    if style.border_thickness > 0 {
        draw_rect(bx, by, bw, bh, style.border_color)
        bx += style.border_thickness
        by += style.border_thickness
        bw -= 2*style.border_thickness
        bh -= 2*style.border_thickness
    }
    draw_rect(bx, by, bw, bh, style.bar_color)
    bw -= style.thumb_width

    if global_active_id == id {
        ratio := clamp(global_mouse_position.x - bx, 0, bw) / bw
        new_value := cast(T)(ratio * value_range)
        updated = new_value != value^
        value^ = new_value
    }

    // thumb
    tw := style.thumb_width
    th := style.thumb_height
    tx := bx + bw * (cast(f32)value^ / value_range)
    ty := y + (h - th)/2
    draw_rect(tx, ty, tw, th, style.thumb_color)
    return
}

slider :: proc(lower_bound, upper_bound: $T, value: ^T, w: Maybe(f32) = nil, h: Maybe(f32) = nil, style := style_slider, loc := #caller_location) -> (updated: bool) {
    layout := get_layout()
    w := w.? or_else compute_layout_item_width(DEFAULT_SLIDER_WIDTH + 2*style.border_thickness)
    h := h.? or_else compute_layout_item_height(max(style.thumb_height, style.bar_height + 2*style.border_thickness))
    updated = slider_floating(layout.xoffset, layout.yoffset, w, h, lower_bound, upper_bound, value, style, loc)
    layout_update(w, h)
    return
}

// header //////////////////////////////////////////////////////////////////////

header_end :: proc() {
    container_pop()
}

@(deferred_none=header_end)
header :: proc(label: string, opened: ^bool, level := 0, w: Maybe(f32) = nil, loc := #caller_location) -> bool {
    id := get_id(loc)

    layout      := get_layout()
    style       := style_header[level]
    symbol      := style.openned_symbol if opened^ else style.closed_symbol
    label_size  := measure_text(label)
    symbol_size := measure_text(symbol)
    width       := w.? or_else compute_layout_item_width(label_size.x + HEADER_SYMBOL_SPACING + symbol_size.x + style.padding.l + style.padding.r + 2*style.border_thickness)
    height      := compute_layout_item_height(max(label_size.y, symbol_size.y) + style.padding.t + style.padding.b + 2*style.border_thickness)
    x, y, w, h  := layout.xoffset, layout.yoffset, width, height

    container_push(id)

    // update globals
    if is_component_clicked(id, x, y, w, h) {
        opened^ = !opened^
    }

    {
        color := style.color
        if global_active_id == id do color = style.pressed_color
        else if global_hot_id == id do color = style.hover_color

        x, y, w, h = draw_base(x, y, w, h, style.border_thickness, 0, color, style.border_color, style.padding)

        // text
        label_x := x
        label_y := y + (h - label_size.y) / 2
        draw_text(label, label_x, label_y, style.text_color)

        // symbol
        symbol_x := x + (w - symbol_size.x)
        symbol_y := y + (h - symbol_size.y) / 2
        draw_text(symbol, symbol_x, symbol_y, style.text_color)
    }

    layout_update(width, height)
    return opened^
}

// text input //////////////////////////////////////////////////////////////////

text_input_floating :: proc(x, y, w, h: f32, builder: ^strings.Builder, style := style_text_input, loc := #caller_location) -> (submitted: bool) {
    @(static) scroll_xoffset : f32 = 0 // used to scroll the text when it goes out of the box
    id := get_id(loc)
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
            case rl.IsKeyPressed(.LEFT)     : command = .Select_Left  if shift else .Left
            case rl.IsKeyPressed(.RIGHT)    : command = .Select_Right if shift else .Right
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

    // this is a single line input so we centered the box on h
    box_h := style_ui.font_size + style.padding.t + style.padding.b
    y += (h - box_h)/2
    h = box_h

    color := style.idle_background_color
    if focused do color = style.focused_background_color
    x, y, w, h = draw_base(x, y, w, h, 1, 0, color, style.border_color, style.padding)

    // text
    content   := strings.to_string(builder^)
    selection := global_edit_state.selection

    begin_clip(x, y, w, h)
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

            draw_text(text_before_selection, x, y, style.selected_text_color)
            x += measure_text(text_before_selection).x

            draw_rect(x, y, selection_size.x, style_ui.font_size, style.selection_color)

            draw_text(text_selected, x, y, style.selected_text_color)
            x += measure_text(text_selected).x

            draw_text(text_after_selection, x, y, style.text_color)
        } else {
            // no selection but focused: draw text and caret
            draw_text(content, x, y, style.text_color)
            caret_index := clamp(selection[0], 0, len(content))
            text_size := measure_text(content[:caret_index])
            draw_rect(x + text_size.x, y, TEXT_INPUT_CARET_SIZE, style_ui.font_size, style.caret_color)
        }
    } else {
        // not focused, draw text
        draw_text(content, x, y, style.text_color)
    }
    end_clip()
    return
}

text_input :: proc(builder: ^strings.Builder, w: Maybe(f32) = nil, h: Maybe(f32) = nil, style := style_text_input, loc := #caller_location) -> (submitted: bool) {
    layout := get_layout()
    text_size := measure_text(strings.to_string(builder^))
    w := w.? or_else compute_layout_item_width(text_size.x + style.padding.l + style.padding.r)
    h := h.? or_else compute_layout_item_height(style_ui.font_size + style.padding.t + style.padding.b)
    submitted = text_input_floating(layout.xoffset, layout.yoffset, w, h, builder, style, loc)
    layout_update(w, h)
    return
}
