-- Library functions.

-- Convert an inclusive scan into an exclusive scan, although without the last
-- element.
let i32_excl_scan_from_incl_scan [k] (scanned: [k]i32) (ne: i32): [k]i32 =
  map (\(i: i32): i32  -> if i == 0 then ne else unsafe scanned[i - 1]) (iota(k))

-- Like scanSegm((+), 0, array, mask).
let i32_plus_scan_segm [k] (array: [k]i32, mask: [k]bool): [k]i32 =
  let (arrayScanned, _) =
    unzip(scan (\(arg0: (i32, bool)) (arg1: (i32, bool)): (i32, bool)  ->
                 let (a0, m0) = arg0
                 let (a1, m1) = arg1
                 let a' = if m1 then a1 else a0 + a1
                 let m' = m0 || m1
                 in (a', m')) (0, false) (
               zip array mask))
  in arrayScanned

-- Get the updating indices through a filter.
let get_updating_indices_alt0 [n] (updating_graph_mask: [n]bool): (*[]i32, i32) =
  let updating_indices = filter (\i -> updating_graph_mask[i]) (iota(n))
  let n_indices = length updating_indices
  in (updating_indices, n_indices)

-- Alternatively, get the updating indices through two maps and a reduce, and
-- let the non-active indices be -1.  This was found to be slower for both small
-- and large datasets.
let get_updating_indices_alt1 [n] (updating_graph_mask: [n]bool): (*[n]i32, i32) =
  let updating_indices = map (\(i: i32): i32  ->
                               if updating_graph_mask[i] then i else -1) (
                             iota(n))
  let zero_ones = map (\(i: i32): i32  ->
                        if updating_graph_mask[i] then 1 else 0) (
                      iota(n))
  let n_indices = reduce (+) 0 (zero_ones)
  in (updating_indices, n_indices)

-- Get the updating indices.
let get_updating_indices(updating_graph_mask: []bool): (*[]i32, i32) =
  get_updating_indices_alt0(updating_graph_mask)
