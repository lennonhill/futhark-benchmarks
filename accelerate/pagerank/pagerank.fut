-- Implementation of the Pagerank example.  The port was carried out
-- by Dan Graakjær Kristensen, Jens Egholm Pedersen and Tobias Sukwon
-- Yoon
--
-- The Accelerate implementation performs some input preprocessing at
-- the same time it is parsed.  The cost of this is measured
-- separately in Accelerate.  Similarly, this implementation requires
-- the input to be presented in a specific form - most importantly,
-- that edges must be sorted according to their target page.  Because
-- Futhark does not directly support fine-grained timing of this kind,
-- we delegate this preprocessing to a separate entry point
-- ('preprocess_graph'), which is not used when benchmarking.  All the
-- data sets listed for this benchmark have already been preprocessed
-- appropriately.
--
-- The reason for this is that the preprocessing is fairly expensive;
-- seemingly corresponding to roughly twenty iterations of the actual
-- Pagerank algorithm.
-- ==
-- input @ data/small.in
-- output @ data/small.out
-- compiled input @ data/random_medium.in
-- output @ data/random_medium.out

type link = {from: i32, to: i32}

import "/futlib/segmented"

module segmented_sum_f32 = segmented_scan {
  type t = f32
  let ne = 0f32
  let op (x: f32) (y: f32) = x + y
}

-- Calculate ranks from pages without any outbound edges
-- This defaults to the page contribution / number of pages
let calculate_dangling_ranks [n] (ranks: [n]f32) (sizes: [n]i32): *[]f32 =
  let zipped = zip sizes ranks
  let weights = map (\(size, rank) -> if size == 0 then rank else 0f32) zipped
  let total = reduce (+) 0f32 weights / f32.i32 n
  in map (+total) ranks

-- Calculate ranks from all pages
-- A rank is counted as the contribution of a page / the outbound edges from that page
-- A contribution is defined as the rank of the page / the inbound edges
let calculate_page_ranks [n] (links: []link) (ranks: *[n]f32) (sizes: [n]i32): *[]f32 =
  let froms = map (\x -> x.from) links
  let tos = map (\x -> x.to) links
  let get_rank (i: i32) = unsafe if sizes[i] == 0 then 0f32
                                 else ranks[i] / f32.i32 sizes[i]
  let contributions = map get_rank froms
  let page_flags = map2 (!=) tos (rotate (-1) tos)
  let scanned_contributions = segmented_sum_f32.segmented_scan page_flags contributions
  let (page_tos, page_contributions) =
    unzip (map3 (\to c flag -> if flag then (to, c) else (-1, c))
                tos scanned_contributions (rotate 1 page_flags))
  in scatter (replicate n 0f32) page_tos page_contributions

let calculate_ranks [n] (links:[]link) (ranks_in: *[n]f32)
                        (sizes: [n]i32) (iterations:i32): *[n]f32 =
  loop ranks = ranks_in for _i < iterations do
    let ranks_pages = calculate_page_ranks links ranks sizes
    in calculate_dangling_ranks ranks_pages sizes

import "/futlib/radix_sort"

module sort_by_to = mk_radix_sort {
  type t = link
  let num_bits = i32.num_bits
  let get_bit (i: i32) (x: link) = i32.get_bit i x.to
}

module sort_by_from = mk_radix_sort {
  type t = link
  let num_bits = i32.num_bits
  let get_bit (i: i32) (x: link) = i32.get_bit i x.from
}

module segmented_sum_i32 = segmented_scan {
  type t = i32
  let ne = 0
  let op (x: i32) (y: i32) = x + y
}

-- Compute the number of outbound links for each page.
let compute_sizes [m] (n: i32) (links: [m]link) =
  let links = sort_by_from.radix_sort links
  let froms = map (\x -> x.from) links
  let flags = map2 (!=) froms (rotate (-1) froms)
  let sizes = segmented_sum_i32.segmented_scan flags (replicate m 1)
  let (sizes, ids, _) = unzip (filter (\(_,_,x) -> x) (zip sizes froms (rotate 1 flags)))
  in scatter (replicate n 0) ids sizes

entry preprocess_graph [m] (links_array: [m][2]i32): ([m]i32, [m]i32, []i32) =
  let links_by_to =
        sort_by_to.radix_sort (map (\l -> {from=l[0], to=l[1]}) links_array)
  let max_to = reduce i32.max 0 (map (\x -> 1 + x.to) links_by_to)
  let n = reduce i32.max max_to (map (\x -> 1 + x.from) links_by_to)
  in (map (\x -> x.from) links_by_to,
      map (\x -> x.to) links_by_to,
      compute_sizes n links_by_to)

let initial_ranks (n: i32): *[n]f32 =
  replicate n (1f32 / r32 n)

let process_graph [m] [n] (links: [m]link) (sizes: [n]i32) (iterations: i32) =
  (calculate_ranks links (initial_ranks n) sizes iterations)

let main [m] (froms: [m]i32) (tos: [m]i32) (sizes: []i32) (iterations: i32) =
  let links = map (\(from, to) -> {from, to}) (zip froms tos)
  in process_graph links sizes iterations