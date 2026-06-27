signature OGG =
sig
  (* A physical Ogg page: its raw header bytes (the 27-byte fixed header plus
     the segment/lacing table) and its body (the concatenated segment data). *)
  type page = { header : Word8Vector.vector, body : Word8Vector.vector }

  (* The parsed fixed page header. `headerType` is the raw flags byte; the
     boolean accessors below decode it.  `lacing` is the segment table. *)
  type header =
    { version    : int
    , headerType : Word8.word
    , granulePos : LargeInt.int    (* 64-bit, little-endian; ~1 for "no packet ends here" *)
    , serialNo   : Word32.word
    , seqNo      : Word32.word
    , crc        : Word32.word
    , lacing     : int list }

  (* The 4-byte "OggS" capture pattern. *)
  val capturePattern : Word8Vector.vector

  (* Split a byte stream into physical pages (skipping junk between captures). *)
  val segment : Word8Vector.vector -> page list

  (* Alias for `segment` with a clearer name. *)
  val pages : Word8Vector.vector -> page list

  (* Parse a page's fixed header + lacing table. Raises Subscript on a header
     too short to contain its declared lacing table. *)
  val parseHeader : page -> header

  (* Flag accessors over `headerType`. *)
  val isContinuation : header -> bool   (* bit 0x01: continued packet *)
  val isBeginOfStream : header -> bool  (* bit 0x02: first page of a logical stream *)
  val isEndOfStream : header -> bool    (* bit 0x04: last page of a logical stream *)

  (* All pages belonging to one logical stream (matching serial number). *)
  val pagesForSerial : Word8Vector.vector -> Word32.word -> page list

  (* Reassemble logical packets from a sequence of pages. A segment of length
     255 continues into the next segment (and, at a page boundary, into the next
     page); any segment < 255 terminates the current packet. A trailing run of
     255s with no terminator yields an incomplete final packet (still returned).
     Pages are taken in the given order. *)
  val packets : page list -> Word8Vector.vector list

  (* Ogg CRC-32 (polynomial 0x04C11DB7, no reflection, init 0) over a byte
     vector.  `checkCrc page` recomputes the page CRC with the stored CRC field
     zeroed and compares it against the header's `crc`. *)
  val crc : Word8Vector.vector -> Word32.word
  val checkCrc : page -> bool
end
