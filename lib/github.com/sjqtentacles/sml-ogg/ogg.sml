structure Ogg :> OGG =
struct
  type page = { header : Word8Vector.vector, body : Word8Vector.vector }
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
end
