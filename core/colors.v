module core

import term.ui as tui
import rand

type Color = tui.Color

fn Color.hsl(h f32, s f32, l f32) Color {
	if s == 0 {
		ll := u8(l)
		return Color{ll, ll, ll}
	}

	qq := if l < 0.5 {
		l * (1 + s)
	} else {
		l + s - (l * s)
	}
	pp := (2 * l) - qq
	return Color{
		r: u8(hue(pp, qq, h + 1.0 / 3.0) * 255)
		g: u8(hue(pp, qq, h) * 255)
		b: u8(hue(pp, qq, h - 1.0 / 3.0) * 255)
	}
}

[inline]
fn Color.random() Color {
	return Color{rand.u8(), rand.u8(), rand.u8()}
}

[inline]
fn Color.pastel() Color {
	// vfmt off
	return Color.hsl(
		rand.f32(),
		rand.f32_in_range(0.25, 0.95) or { panic('fn Color.pastel(): this should never happen.') },
		0.75 // rand.f32_in_range(0.75, 0.9) or { panic('fn Color.pasetl(): this should never happen.') }
	)
	// vfmt on
}

fn hue(p f32, q f32, _t f32) f32 {
	// vfmt off
	mut t := _t
	if t < 0 { t += 1 }
	if t > 1 { t -= 1 }
	if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
	if t < 1.0 / 2.0 { return q }
	if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6	}
	return p
	// vfmt on
}
