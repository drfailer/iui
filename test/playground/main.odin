package playground

import "olib:ui"
import "core:fmt"
import rl "vendor:raylib"

FONT_SIZE :: 20

get_id :: proc(loc := #caller_location) -> ui.Id {
    return ui.get_id(loc, 0)
}

main :: proc() {
    ui.init()
    defer ui.fini()
    fmt.printfln("hash test: {}", get_id())
    fmt.printfln("hash test: {}", get_id())

    button1_click_count := 0
    button2_click_count := 0

    rl.InitWindow(800, 600, "Playground")
    defer rl.CloseWindow()


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

        ui.fini_frame()
    }
}
