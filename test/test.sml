structure Tests = struct
  open Harness
  structure O = Ogg
  fun w i = Word8.fromInt i
  fun toStr v =
    String.implode (List.tabulate (Word8Vector.length v,
        fn i => Char.chr (Word8.toInt (Word8Vector.sub (v, i)))))

  (* Build one real OggS page: 27-byte fixed header + segCount lacing values +
     body.  Fixed header layout: "OggS"(4) version(1) type(1) granule(8)
     serial(4) seq(4) checksum(4) = 26 bytes, then the segment-count byte. *)
  fun mkPage (laces, body) =
    let
      val pre = [0x4F,0x67,0x67,0x53, 0,0, 0,0,0,0,0,0,0,0, 1,0,0,0, 0,0,0,0, 0,0,0,0]
      val segc = [List.length laces]
      val bodyBytes = List.map Char.ord (String.explode body)
    in pre @ segc @ laces @ bodyBytes end

  fun run () = let
    val () = section "capture pattern"
    val () = checkInt "len 4" (4, Word8Vector.length O.capturePattern)
    val () = checkString "is OggS" ("OggS", toStr O.capturePattern)

    val () = section "page segmentation (real parse)"
    (* two junk bytes, then two pages; segment must skip junk via findPage *)
    val raw = [0xAA, 0xBB] @ mkPage ([3,2], "ABCDE") @ mkPage ([4], "WXYZ")
    val v = Word8Vector.fromList (List.map w raw)
    val pages = O.segment v
    val () = checkInt "found two pages" (2, List.length pages)

    val p1 = List.nth (pages, 0)
    val () = checkInt "p1 header len 29" (29, Word8Vector.length (#header p1))  (* 27 + 2 laces *)
    val () = checkInt "p1 body len 5"  (5, Word8Vector.length (#body p1))
    val () = checkString "p1 body bytes" ("ABCDE", toStr (#body p1))

    val p2 = List.nth (pages, 1)
    val () = checkInt "p2 header len 28" (28, Word8Vector.length (#header p2))  (* 27 + 1 lace *)
    val () = checkInt "p2 body len 4"  (4, Word8Vector.length (#body p2))
    val () = checkString "p2 body bytes" ("WXYZ", toStr (#body p2))

    val () = section "no capture pattern -> no pages"
    val () = checkInt "empty result" (0,
               List.length (O.segment (Word8Vector.fromList (List.map w [1,2,3,4,5]))))
  in Harness.run () end
end
