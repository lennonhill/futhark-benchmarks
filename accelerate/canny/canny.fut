-- Port of the canny example from Accelerate:
-- https://github.com/AccelerateHS/accelerate-examples/blob/master/examples/canny/src-acc
--
-- Only implements the first seven[sic] data-parallel stages, not the final
-- recursive algorithm (which in the Accelerate implementation is also
-- done in Repa).
--
-- ==
-- nobench input {
--   50f32
--   100f32
--   [[2092830683i32, 1394728708i32, -33326269i32],
--    [1986857019i32, 1313352304i32, -424163480i32],
--    [1813961220i32, -967167319i32, -503802777i32],
--    [-2133263610i32, -1327310708i32, -1863700019i32],
--    [-873352195i32, -1591419765i32, 378033750i32]]
-- }
-- output {
--   [1, 4, 6, 7]
-- }
--
-- compiled input @ data/lena256.in
-- output @ data/lena256.out
--
-- compiled input @ data/lena512.in
-- output @ data/lena512.out

import "/futlib/math"

default (f32)

let luminanceOfRGBA32(p: i32): f32 =
  let r = i8(p >> 24)
  let g = i8(p >> 16)
  let b = i8(p >> 8)
  let r' = 0.3  * f32(r)
  let g' = 0.59 * f32(g)
  let b' = 0.11 * f32(b)
  in (r' + g' + b') / 255.0

let clamp(lower: i32, x: i32, upper: i32): i32 =
  i32.max lower (i32.min upper x)

let orientUndef: i32 = 0
let orientPosD: i32 = 64
let orientVert: i32 = 128
let orientNegD: i32 = 192
let orientHoriz: i32 = 255

let edgeNone: f32 = 0.0
let edgeWeak: f32 = 0.5
let edgeStrong: f32 = 1.0

let toGreyscale(img: *[#h][#w]i32): *[h][w]f32 =
  map (\(row: [#w]i32): [w]f32  ->
        map (255.0*) (map luminanceOfRGBA32 row)) img

let gaussianX [h][w] (img: *[h][w]f32): *[h][w]f32 =
  unsafe
  map (\(x: i32): [w]f32  ->
        map (\(y: i32): f32  ->
              let a = img[clamp(0,x-2,h-1),y] * (1.0 / 16.0)
              let b = img[clamp(0,x-1,h-1),y] * (4.0 / 16.0)
              let c = img[clamp(0,x+0,h-1),y] * (6.0 / 16.0)
              let d = img[clamp(0,x+1,h-1),y] * (4.0 / 16.0)
              let e = img[clamp(0,x+2,h-1),y] * (1.0 / 16.0)
              in a + b + c + d + e)
            (iota w))
      (iota h)

let gaussianY [h][w] (img: *[h][w]f32): *[h][w]f32 =
  unsafe
  map (\(x: i32): [w]f32  ->
        map (\(y: i32): f32  ->
              unsafe
              let a = img[x,clamp(0,y-2,w-1)] * (1.0 / 16.0)
              let b = img[x,clamp(0,y-1,w-1)] * (4.0 / 16.0)
              let c = img[x,clamp(0,y+0,w-1)] * (6.0 / 16.0)
              let d = img[x,clamp(0,y+1,w-1)] * (4.0 / 16.0)
              let e = img[x,clamp(0,y+2,w-1)] * (1.0 / 16.0)
              in a + b + c + d + e)
       (iota w))
     (iota h)

let gradiantMagDir [h][w] (low: f32, img: *[h][w]f32): [h][w](f32,i32) =
  unsafe
  map (\(x: i32): [w](f32,i32)  ->
        map (\(y: i32): (f32,i32)  ->
              unsafe
              let v0 = img[clamp(0, x-1, h-1), clamp(0, y-1, w-1)]
              let v1 = img[clamp(0, x+0, h-1), clamp(0, y-1, w-1)]
              let v2 = img[clamp(0, x+1, h-1), clamp(0, y-1, w-1)]

              let v3 = img[clamp(0, x-1, h-1), clamp(0, y+0, w-1)]
              let v4 = img[clamp(0, x+1, h-1), clamp(0, y+0, w-1)]

              let v5 = img[clamp(0, x-1, h-1), clamp(0, y+1, w-1)]
              let v6 = img[clamp(0, x+0, h-1), clamp(0, y+1, w-1)]
              let v7 = img[clamp(0, x+1, h-1), clamp(0, y+1, w-1)]

              let dx = v2 + (2.0*v4) + v7 - v0 - (2.0*v3) - v5
              let dy = v0 + (2.0*v1) + v2 - v5 - (2.0*v6) - v7

              let mag = f32.sqrt(dx * dx + dy * dy)

              let theta = f32.atan2 dy dx
              let alpha = (theta - (f32.pi/8.0)) * (4.0/f32.pi)

              -- Normalise the angle to between [0..8)
              let norm = alpha + if alpha <= 0.0 then 8.0 else 0.0

              let dir = if f32.abs(dx) <= low && f32.abs(dy) <= low
                        then 0
                        else i32.min (64 * (1 + i32(norm) % 4)) 255

              in (mag, dir))
            (iota w))
      (iota h)

let nonMaximumSuppression [h][w] (low: f32, high: f32, magdir: [h][w](f32,i32)): *[h][w]f32 =
  unsafe
  map (\(x: i32): [w]f32  ->
        map (\(y: i32): f32  ->
              let (mag, dir) = magdir[x,y]
              let offsetx = if dir > orientVert then -1
                            else if dir < orientVert then 1
                            else 0
              let offsety = if dir < orientHoriz then -1 else 0
              let (fwd, _) = magdir[clamp(0, x+offsetx, h-1),
                                    clamp(0, y+offsety, w-1)]
              let (rev, _) = magdir[clamp(0, x-offsetx, h-1),
                                    clamp(0, y-offsety, w-1)]

              in if dir == orientUndef || mag < low || mag < fwd || mag < rev
                 then 0.0
                 else if mag >= high then 1.0 else 0.5)
            (iota w))
      (iota h)

let selectStrong [h][w] (img: *[h][w]f32): []i32 =
  let strong = map (\(x: f32): i32  ->
                     if x == edgeStrong then 1 else 0)
                   (reshape (h*w) img)
  -- The original Accelerate implementation used an exclusive scan
  -- here, so we have to play with the indices.
  let targetIdxAndLen = scan (+) 0 strong
  let (targetIdx, len') = split ((shape strong)[0]-1) targetIdxAndLen
  let len = len'[0]
  let zeros = replicate len 0
  let (indices', values) =
    unzip(map (\i target_i strong_x ->
                if strong_x == 0
                then (-1, 0)
                else (target_i, i+1))
              (iota(w*h-1)) targetIdx strong[1:])
  in scatter zeros indices' values

let main [h][w] (low: f32, high: f32, img: *[h][w]i32): []i32 =
  selectStrong
  (nonMaximumSuppression
   (low, high, gradiantMagDir
    (low, gaussianY
     (gaussianX
      (toGreyscale(img))))))
