structure Ogg :> OGG =
struct
  type page = { header : Word8Vector.vector, body : Word8Vector.vector }

  type header =
    { version    : int
    , headerType : Word8.word
    , granulePos : LargeInt.int
    , serialNo   : Word32.word
    , seqNo      : Word32.word
    , crc        : Word32.word
    , lacing     : int list }

  val capturePattern = Word8Vector.fromList [0wx4F, 0wx67, 0wx67, 0wx53]

  fun take n v off =
    Word8Vector.tabulate (n, fn i => Word8Vector.sub (v, off + i))

  fun findPage v off =
    if off + 4 > Word8Vector.length v then NONE
    else if Word8Vector.sub (v,off)=0wx4F andalso Word8Vector.sub (v,off+1)=0wx67
         andalso Word8Vector.sub (v,off+2)=0wx67 andalso Word8Vector.sub (v,off+3)=0wx53
    then SOME off else findPage v (off + 1)

  fun readPage v off =
    let val segCount = Word8.toInt (Word8Vector.sub (v, off + 26))
        val hdrLen = 27 + segCount
        val segs = List.tabulate (segCount, fn i => Word8.toInt (Word8Vector.sub (v, off + 27 + i)))
        val bodyLen = List.foldl op+ 0 segs
        val header = take hdrLen v off
        val body = take bodyLen v (off + hdrLen)
    in { header = header, body = body } end

  fun segment v =
    let fun loop off acc =
          case findPage v off of
              NONE => List.rev acc
            | SOME p =>
                let val pg = readPage v p
                    val next = p + Word8Vector.length (#header pg) + Word8Vector.length (#body pg)
                in loop next (pg :: acc) end
    in loop 0 [] end

  val pages = segment

  (* Little-endian integer readers over a header vector. *)
  fun le32 h off : Word32.word =
    let fun b i = Word32.fromInt (Word8.toInt (Word8Vector.sub (h, off + i)))
    in Word32.orb (b 0,
        Word32.orb (Word32.<< (b 1, 0w8),
         Word32.orb (Word32.<< (b 2, 0w16), Word32.<< (b 3, 0w24)))) end

  fun le64 h off : LargeInt.int =
    let fun b i = LargeInt.fromInt (Word8.toInt (Word8Vector.sub (h, off + i)))
        fun pow256 0 = (1 : LargeInt.int) | pow256 i = 256 * pow256 (i - 1)
        val terms = List.tabulate (8, fn i => b i * pow256 i)
    in List.foldl (op +) 0 terms end

  fun parseHeader ({header=h, ...} : page) : header =
    let val segCount = Word8.toInt (Word8Vector.sub (h, 26))
        val lacing = List.tabulate (segCount, fn i => Word8.toInt (Word8Vector.sub (h, 27 + i)))
    in { version    = Word8.toInt (Word8Vector.sub (h, 4))
       , headerType = Word8Vector.sub (h, 5)
       , granulePos = le64 h 6
       , serialNo   = le32 h 14
       , seqNo      = le32 h 18
       , crc        = le32 h 22
       , lacing     = lacing } end

  fun isContinuation  (hd : header) = Word8.andb (#headerType hd, 0wx01) <> 0w0
  fun isBeginOfStream (hd : header) = Word8.andb (#headerType hd, 0wx02) <> 0w0
  fun isEndOfStream   (hd : header) = Word8.andb (#headerType hd, 0wx04) <> 0w0

  fun pagesForSerial v serial =
    List.filter (fn pg => #serialNo (parseHeader pg) = serial) (segment v)

  (* Packet reassembly. Walk pages in order; within each page split the body by
     the lacing table: accumulate segment bytes, and whenever a lacing value is
     < 255 close the current packet. A 255 lacing continues into the next
     segment (and across the page boundary). Any leftover bytes at the very end
     (a packet whose final lacing was 255) are emitted as an incomplete packet. *)
  fun packets pgs =
    let
      fun concatRev chunks =
        Word8Vector.concat (List.rev chunks)

      (* state: cur = reversed list of byte-chunks for the in-progress packet;
                 acc = reversed list of finished packets. *)
      fun overPage (pg, (cur, acc)) =
        let
          val hd = parseHeader pg
          val body = #body pg
          (* offsets of each segment within the body *)
          fun go ([], _, cur, acc) = (cur, acc)
            | go (lace :: rest, off, cur, acc) =
                let val chunk = take lace body off
                    val cur' = chunk :: cur
                    val off' = off + lace
                in if lace < 255
                   then go (rest, off', [], (concatRev cur' :: acc))  (* packet ends *)
                   else go (rest, off', cur', acc)                    (* continues *)
                end
        in go (#lacing hd, 0, cur, acc) end

      val (cur, acc) = List.foldl overPage ([], []) pgs
      val acc' = if null cur then acc else (concatRev cur :: acc)   (* incomplete tail *)
    in List.rev acc' end

  (* Ogg CRC-32: poly 0x04C11DB7, init 0, no input/output reflection, no final
     XOR. Computed MSB-first. *)
  val crcTable : Word32.word vector =
    Vector.tabulate (256, fn n =>
      let
        val r0 = Word32.<< (Word32.fromInt n, 0w24)
        fun step (r : Word32.word) =
          if Word32.andb (r, 0wx80000000) <> 0w0
          then Word32.xorb (Word32.<< (r, 0w1), 0wx04c11db7)
          else Word32.<< (r, 0w1)
        fun iter (0, r) = r | iter (k, r) = iter (k - 1, step r)
      in iter (8, r0) end)

  fun crc v =
    let
      val n = Word8Vector.length v
      fun loop (i, r) =
        if i >= n then r
        else
          let val byte = Word32.fromInt (Word8.toInt (Word8Vector.sub (v, i)))
              val idx = Word32.andb (Word32.xorb (Word32.>> (r, 0w24), byte), 0wxFF)
              val tbl = Vector.sub (crcTable, Word32.toInt idx)
          in loop (i + 1, Word32.xorb (Word32.<< (r, 0w8), tbl)) end
    in loop (0, 0w0) end

  fun checkCrc (pg as {header=h, body} : page) =
    let
      val hd = parseHeader pg
      val hlen = Word8Vector.length h
      (* full page bytes with the 4 CRC bytes (offset 22..25) zeroed *)
      val full = Word8Vector.concat [h, body]
      val zeroed = Word8Vector.tabulate (Word8Vector.length full,
                     fn i => if i >= 22 andalso i < 26 then 0w0 else Word8Vector.sub (full, i))
    in crc zeroed = #crc hd end
end
