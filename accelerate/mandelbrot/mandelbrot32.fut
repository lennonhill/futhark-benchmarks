-- Mandelbrot visualisation with 32-bit floats.

import "generic_mandelbrot"

module mandelbrot = mandelbrot f32

entry render_mandelbrot (screenX: i32) (screenY: i32)
                        (xcentre: f64) (ycentre: f64) (width: f64)
                        (limit: i32) (radius: f64)
                        : [screenY][screenX]i32 =
  mandelbrot.render_mandelbrot screenX screenY (f32.f64 xcentre) (f32.f64 ycentre) (f32.f64 width) limit (f32.f64 radius)
