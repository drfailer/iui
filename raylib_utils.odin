package ui

import "core:c"
import "core:strings"
import rl "vendor:raylib"

// text ////////////////////////////////////////////////////////////////////////

//
// This is a port raylib's DrawTextEx and MeasureTextEx functions that use odin
// strings instead of cstrings to avoid conversions (for conveniency and
// efficiency).
//
// The draw_text function also returns the drawn text size which is useful in
// some situations.
//

rl_draw_text_ex :: proc(font: rl.Font, text: string, position: rl.Vector2, font_size: f32, spacing: f32, tint: rl.Color) -> (offset: [2]f32) {
	font := font
    if font.texture.id == 0 do font = rl.GetFontDefault()  // Security check in case of not valid font

    size := len(text);    // Total size in bytes of the text, scanned by codepoints in loop

    text_offset_x, text_offset_y: f32
    scale_factor := font_size / f32(font.baseSize)

    for i := 0; i < size; {
        // Get next codepoint from byte string and glyph index in font
        codepoint_byte_count: c.int
        codepoint := rl.GetCodepointNext(strings.unsafe_string_to_cstring(text[i:]), &codepoint_byte_count) // todo: this is unsafe because there is not 0 at the end of the given string
        index := rl.GetGlyphIndex(font, codepoint)

        if codepoint == '\n' {
            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            // todo: we don't have access to textLineSpacing from Odin
            text_offset_y += (font_size + 0);
            text_offset_x = 0;
        } else if codepoint != '\r' {
            if (codepoint != ' ') && (codepoint != '\t') {
                rl.DrawTextCodepoint(font, codepoint, (rl.Vector2){ position.x + text_offset_x, position.y + text_offset_y }, font_size, tint)
            }

            if font.glyphs[index].advanceX == 0 {
            	text_offset_x += (cast(f32)font.recs[index].width*scale_factor + spacing)
            } else {
            	text_offset_x += (cast(f32)font.glyphs[index].advanceX*scale_factor + spacing)
            }
        }

        i += int(codepoint_byte_count)   // Move text bytes counter to next codepoint
    }
    return {text_offset_x, text_offset_y}
}

rl_measure_text :: proc(font: rl.Font, text: string, font_size, spacing: f32) -> (text_size: [2]f32) {
    if font.texture.id == 0 || len(text) == 0 do return // Security check

    size := len(text)
    temp_byte_counter, byte_counter: int

    text_w, temp_text_w: f32
    text_h := font_size
    scale_factor := font_size / f32(font.baseSize)

    for i := 0; i < size; {
        byte_counter += 1

        codepoint_byte_count: c.int
        letter := rl.GetCodepointNext(strings.unsafe_string_to_cstring(text[i:]), &codepoint_byte_count)
        index := rl.GetGlyphIndex(font, letter);

        i += int(codepoint_byte_count)

        if letter != '\n' {
            if font.glyphs[index].advanceX > 0 {
                text_w += cast(f32)font.glyphs[index].advanceX
            } else {
                text_w += (font.recs[index].width + cast(f32)font.glyphs[index].offsetX)
            }
        } else {
            if temp_text_w < text_w do temp_text_w = text_w
            byte_counter = 0
            text_w = 0

            // NOTE: Line spacing is a global variable, use SetTextLineSpacing() to setup
            // todo: again, we don't have access to textLineSpacing...
            text_h += (font_size + 0)
        }

        if temp_byte_counter < byte_counter do temp_byte_counter = byte_counter
    }

    if temp_text_w < text_w do temp_text_w = text_w

    text_size.x = temp_text_w*scale_factor + f32((temp_byte_counter - 1)*int(spacing))
    text_size.y = text_h

    return text_size
}
