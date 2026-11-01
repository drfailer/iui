package playground

import "olib:iui"
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

    iui.init()
    defer iui.fini()

    // iui.style_ui.font      = rl.LoadFontEx("/usr/share/fonts/TTF/IBMPlexMono-Regular.ttf", FONT_SIZE, nil, 0)
    iui.style_ui.font      = rl.LoadFontEx("/usr/share/fonts/google-noto-vf/NotoSansMono[wght].ttf", FONT_SIZE, nil, 0)
    iui.style_ui.font_size = FONT_SIZE
    defer rl.UnloadFont(iui.style_ui.font)

    for !rl.WindowShouldClose() {
        rl.ClearBackground(rl.GetColor(0x222222ff))
        iui.init_frame(cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight())

        iui.text("some text")
        if iui.pane({0, 0, 255, 255}, padding = {10, 10, 10, 10}) {
            if iui.row(padding = {4, 4, 4, 4}, item_widths = {150, 0}, item_spacing = 10) {

                @(static) buttons_header_status: bool
                if iui.header("header", &buttons_header_status) {
                    iui.text("test")
                }

                if iui.column(item_spacing = 4) {
                    if iui.button("button 2") {
                        button2_click_count += 1
                        fmt.println("button 2 cliked ", button2_click_count)
                    }

                    if iui.row(item_spacing = 4) {
                        if iui.button("button 1") {
                            button1_click_count += 1
                            fmt.println("button 1 cliked", button1_click_count)
                        }

                        if iui.button("button 1") {
                            button1_click_count += 1
                            fmt.println("button 1 cliked", button1_click_count)
                        }
                    }

                    if iui.button("button 2") {
                        button2_click_count += 1
                        fmt.println("button 2 cliked ", button2_click_count)
                    }
                }

                if iui.box(200, 200) {
                    layout := iui.get_layout()
                    x, y := layout.xoffset, layout.yoffset
                    iui.draw_rect(x + 1, y + 1, 198, 198, {0, 255, 0, 255})
                    iui.draw_rect(x, y, 200, 200, {255, 0, 0, 255})
                }

                if iui.column(100, item_spacing = 4) {
                    @(static) opt1: bool
                    if iui.checkbox("opt1", &opt1) {
                        fmt.println("opt1:", opt1)
                    }

                    @(static) opt2: bool
                    if iui.checkbox("opt2", &opt2) {
                        fmt.println("opt2:", opt2)
                    }

                    @(static) opt3: bool
                    if iui.checkbox("opt3", &opt3) {
                        fmt.println("opt3:", opt3)
                    }

                    if iui.button("submit") {
                        fmt.println("submit")
                    }

                    @(static) value := 50
                    if iui.slider(0, 100, &value) {
                        fmt.println("value changed:", value)
                    }
                    iui.textf("value: {}", value)

                    if iui.text_input(&input_builder, w = 200) {
                        fmt.println("text submitted: ", strings.to_string(input_builder))
                    }

                }
            }
        }

        iui.fini_frame()
    }
}
