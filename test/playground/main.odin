package playground

import "olib:ui"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

FONT_SIZE :: 20

main :: proc() {
    button1_click_count := 0
    button2_click_count := 0

    input_builder: strings.Builder
    strings.builder_init(&input_builder)
    defer strings.builder_destroy(&input_builder)
    strings.write_string(&input_builder, "default text")

    rl.InitWindow(800, 600, "Playground")
    defer rl.CloseWindow()

    ui.init()
    defer ui.fini()

    // ui.style_ui.font      = rl.LoadFontEx("/usr/share/fonts/TTF/IBMPlexMono-Regular.ttf", FONT_SIZE, nil, 0)
    ui.style_ui.font      = rl.LoadFontEx("/usr/share/fonts/google-noto-vf/NotoSansMono[wght].ttf", FONT_SIZE, nil, 0)
    ui.style_ui.font_size = FONT_SIZE
    defer rl.UnloadFont(ui.style_ui.font)

    for !rl.WindowShouldClose() {
        rl.ClearBackground(rl.GetColor(0x222222ff))
        ui.init_frame()

        ui.text("some text")
        if ui.pane({0, 0, 255, 255}, padding = {10, 10, 10, 10}) {
            if ui.row(padding = {4, 4, 4, 4}, item_spacing = 10) {

                @(static) buttons_header_status: bool
                if ui.header("header", &buttons_header_status) {
                    ui.text("test")
                }

                if ui.column(item_spacing = 4) {
                    if ui.button("button 2") {
                        button2_click_count += 1
                        fmt.println("button 2 cliked ", button2_click_count)
                    }

                    if ui.row(item_spacing = 4) {
                        if ui.button("button 1") {
                            button1_click_count += 1
                            fmt.println("button 1 cliked", button1_click_count)
                        }

                        if ui.button("button 1") {
                            button1_click_count += 1
                            fmt.println("button 1 cliked", button1_click_count)
                        }
                    }

                    if ui.button("button 2") {
                        button2_click_count += 1
                        fmt.println("button 2 cliked ", button2_click_count)
                    }
                }

                if ui.box(200, 200) {
                    layout := ui.get_layout()
                    x, y := layout.xoffset, layout.yoffset
                    ui.draw_rect(x, y, 200, 200, {255, 0, 0, 255})
                    ui.draw_rect(x + 1, y + 1, 198, 198, {0, 255, 0, 255})
                }

                if ui.column(100, item_spacing = 4) {
                    @(static) opt1: bool
                    if ui.checkbox("opt1", &opt1) {
                        fmt.println("opt1:", opt1)
                    }

                    @(static) opt2: bool
                    if ui.checkbox("opt2", &opt2) {
                        fmt.println("opt2:", opt2)
                    }

                    @(static) opt3: bool
                    if ui.checkbox("opt3", &opt3) {
                        fmt.println("opt3:", opt3)
                    }

                    if ui.button("submit") {
                        fmt.println("submit")
                    }

                    @(static) value := 50
                    if ui.slider(0, 100, &value) {
                        fmt.println("value changed:", value)
                    }
                    ui.textf("value: {}", value)

                    if ui.text_input(&input_builder, w = 200) {
                        fmt.println("text submitted: ", strings.to_string(input_builder))
                    }

                }
            }
        }

        ui.fini_frame()
    }
}
