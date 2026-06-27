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

  (* little-endian byte split via repeated div/mod (avoids large powers that
     would overflow a 32-bit default Int under MLton) *)
  fun bytesLE (count, n) =
    let fun go (0, _) = []
          | go (k, x) = (x mod 256) :: go (k - 1, x div 256)
    in go (count, n) end
  fun le32bytes n = bytesLE (4, n)
  fun le64bytes n = bytesLE (8, n)

  (* Page with explicit flags / granule / serial / seq, CRC left 0. bodyBytes is
     a list of int byte values. *)
  fun mkPageFull {flags, granule, serial, seq, laces, bodyBytes} =
    let
      val pre = [0x4F,0x67,0x67,0x53, 0, flags]
                @ le64bytes granule
                @ le32bytes serial
                @ le32bytes seq
                @ [0,0,0,0]                 (* crc, zeroed *)
      val segc = [List.length laces]
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

    val () = section "parseHeader fields"
    val pf = mkPageFull {flags=0x02, granule=258, serial=0xCAFE, seq=7,
                         laces=[3,255], bodyBytes=List.tabulate (258, fn i => i mod 256)}
    val vf = Word8Vector.fromList (List.map w pf)
    val pg = hd (O.segment vf)
    val h = O.parseHeader pg
    val () = checkInt "version 0" (0, #version h)
    val () = checkInt "granule 258" (258, LargeInt.toInt (#granulePos h))
    val () = checkInt "serial 0xCAFE" (0xCAFE, Word32.toInt (#serialNo h))
    val () = checkInt "seq 7" (7, Word32.toInt (#seqNo h))
    val () = checkIntList "lacing [3,255]" ([3,255], #lacing h)
    val () = checkBool "isBeginOfStream" (true, O.isBeginOfStream h)
    val () = checkBool "isEndOfStream false" (false, O.isEndOfStream h)
    val () = checkBool "isContinuation false" (false, O.isContinuation h)

    val () = section "flag decoding (continuation + eos)"
    val pf2 = mkPageFull {flags=0x05, granule=0, serial=1, seq=0, laces=[0], bodyBytes=[]}
    val h2 = O.parseHeader (hd (O.segment (Word8Vector.fromList (List.map w pf2))))
    val () = checkBool "continuation" (true, O.isContinuation h2)
    val () = checkBool "eos" (true, O.isEndOfStream h2)
    val () = checkBool "not bos" (false, O.isBeginOfStream h2)

    val () = section "pagesForSerial filters by stream"
    val mixed = mkPageFull {flags=0, granule=0, serial=10, seq=0, laces=[2], bodyBytes=[65,66]}
              @ mkPageFull {flags=0, granule=0, serial=20, seq=0, laces=[2], bodyBytes=[67,68]}
              @ mkPageFull {flags=0, granule=0, serial=10, seq=1, laces=[2], bodyBytes=[69,70]}
    val vm = Word8Vector.fromList (List.map w mixed)
    val s10 = O.pagesForSerial vm (Word32.fromInt 10)
    val () = checkInt "two pages for serial 10" (2, List.length s10)
    val () = checkString "first serial-10 body" ("AB", toStr (#body (hd s10)))

    val () = section "packet reassembly (single page, two packets)"
    val sp = mkPageFull {flags=0, granule=0, serial=1, seq=0, laces=[3,2],
                         bodyBytes=[1,2,3, 4,5]}
    val pkts = O.packets (O.segment (Word8Vector.fromList (List.map w sp)))
    val () = checkInt "two packets" (2, List.length pkts)
    val () = checkInt "packet A len 3" (3, Word8Vector.length (List.nth (pkts,0)))
    val () = checkInt "packet B len 2" (2, Word8Vector.length (List.nth (pkts,1)))

    val () = section "packet reassembly across pages (255 continuation)"
    val pageA = mkPageFull {flags=0x02, granule=0, serial=1, seq=0, laces=[255],
                            bodyBytes=List.tabulate (255, fn _ => 0xAB)}
    val pageB = mkPageFull {flags=0x01, granule=0, serial=1, seq=1, laces=[10],
                            bodyBytes=List.tabulate (10, fn _ => 0xCD)}
    val pk2 = O.packets (O.segment (Word8Vector.fromList (List.map w (pageA @ pageB))))
    val () = checkInt "one reassembled packet" (1, List.length pk2)
    val () = checkInt "reassembled length 265" (265, Word8Vector.length (hd pk2))

    val () = section "CRC32 round-trip"
    val rawPage = mkPageFull {flags=0, granule=0, serial=42, seq=0, laces=[4],
                              bodyBytes=[0xDE,0xAD,0xBE,0xEF]}
    val zeroedVec = Word8Vector.fromList (List.map w rawPage)
    val computed = O.crc zeroedVec
    fun byteOfW32 (x, i) = Word32.toInt (Word32.andb (Word32.>> (x, Word.fromInt (8*i)), 0wxFF))
    val crcBytes = List.tabulate (4, fn i => byteOfW32 (computed, i))
    val withCrc =
      List.tabulate (List.length rawPage, fn i =>
        if i >= 22 andalso i < 26 then List.nth (crcBytes, i - 22) else List.nth (rawPage, i))
    val goodPage = hd (O.segment (Word8Vector.fromList (List.map w withCrc)))
    val () = checkBool "checkCrc accepts valid page" (true, O.checkCrc goodPage)
    val () = checkBool "checkCrc rejects original (crc=0) page"
               (false, O.checkCrc (hd (O.segment zeroedVec)))
  in Harness.run () end
end
