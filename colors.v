import term.ui as tui
import rand
import rand.seed
import time

struct Color {
	r int
	g int
	b int
}

fn from<T>(x T) Color {
	match typeof(x).name {
		'int' {
			r := (x>>16)&0x0ff
			g := (rxgb>>8) &0x0ff
			b := (x) &0x0ff
			return Color{
				r: r
				g: g
				b: b
			}
		}
		'ui.Color' {
			return Color{
				r: x.r.int()
				g: x.g.int()
				b: x.b.int()
			}
		}
		else {
			return Color{}
		}
	}
}

fn (c1 Color) == (c2 Color) bool {
	if c1.int() == c2.int() {
		return true
	} else {
		return false
	}
}

fn (c1 Color) < (c2 Color) bool {
	if c1.int() < c2.int() {
		return true
	} else {
		return false
	}
}

fn (c Color) int() int {
	return ((c.r & 0x0ff) << 16) | ((c.g & 0x0ff) << 8) | (c.b & 0x0ff)
}

fn (c Color) to_tui_color() tui.Color {
	return tui.Color{
		r: byte(c.r)
		g: byte(c.g)
		b: byte(c.b)
	}
}

fn (colors []Color) int() []int {
	mut arr := []int{}
	for color in colors {
		arr << color.int()
	}
	return arr
}

fn sort(mut colors []Color) {
	quick_sort(mut colors, 0, colors.len - 1)
}

fn quick_sort(mut colors []Color, low int, high int) {
	if low < high {
		pidx := partition(mut colors, low, high)

		quick_sort(mut colors, low, pidx - 1)
		quick_sort(mut colors, pidx + 1, high)
	}
}

fn partition(mut colors []Color, low int, high int) int {
	pivot := colors[high]
	mut i := low - 1
	for j := low; j < high; j++ {
		if colors[j] <= pivot {
			i++
			tmp := colors[i]
			colors[i] = colors[j]
			colors[j] = tmp
		}
	}

	tmp := colors[i + 1]
	colors[i + 1] = colors[high]
	colors[high] = tmp

	return i + 1
}
