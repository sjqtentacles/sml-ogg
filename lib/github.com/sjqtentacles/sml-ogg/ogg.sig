signature OGG =
sig
  type page = { header : Word8Vector.vector, body : Word8Vector.vector }
  val segment : Word8Vector.vector -> page list
  val capturePattern : Word8Vector.vector
end
