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

    ui.style_ui.font      = rl.LoadFontEx("/usr/share/fonts/TTF/IBMPlexMono-Regular.ttf", FONT_SIZE, nil, 0)
    ui.style_ui.font_size = FONT_SIZE
    defer rl.UnloadFont(ui.style_ui.font)

    for !rl.WindowShouldClose() {
        rl.ClearBackground(rl.GetColor(0x303030ff))
        ui.init_frame()

        if ui.row() {
            ui.set_layout_padding({4, 4, 4, 4})
            ui.set_layout_item_spacing(4)

            if ui.column() {
                ui.set_layout_item_spacing(4)

                if ui.button("button 2") {
                    button2_click_count += 1
                    fmt.println("button 2 cliked ", button2_click_count)
                }

                if ui.row() {
                    ui.set_layout_item_spacing(4)

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
                rl.DrawRectangleRec(rl.Rectangle{layout.xoffset, layout.yoffset, 200, 200}, rl.Color{255, 0, 0, 255})
            }
            ui.button("Second row button")
        }

        if ui.text_input_floating(&input_builder, 100, 100, 200, 200) {
            fmt.println("text submitted: ", strings.to_string(input_builder))
        }

        ui.fini_frame()
    }
}
