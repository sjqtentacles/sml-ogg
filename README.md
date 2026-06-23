# sml-ogg

[![CI](https://github.com/sjqtentacles/sml-ogg/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-ogg/actions/workflows/ci.yml)

Ogg container **page segmentation** for Standard ML. Scans a byte vector for
`OggS` capture patterns and splits it into pages, parsing the page header's
segment (lacing) table to compute each page's body length.

## API

```sml
type page = { header : Word8Vector.vector, body : Word8Vector.vector }

Ogg.capturePattern         (* the 4-byte "OggS" marker *)
Ogg.segment bytes          (* -> page list *)
```

`segment` walks the stream: it finds the next `OggS` page, reads the
segment-count byte and that many lacing values, sums them to get the body
length, slices out the `header`/`body`, and continues from the end of the page.

```sml
val pages = Ogg.segment bytes
List.length pages                         (* number of Ogg pages *)
Word8Vector.length (#body (hd pages))     (* first page payload size *)
```

## Scope and limitations

- **Container framing only.** This separates Ogg pages; it does not decode any
  codec carried inside them (Vorbis, Opus, FLAC-in-Ogg, etc.).
- Page CRC checksums are not validated, and granule position / serial number /
  page sequence fields are not interpreted.
- Continued-packet flags across page boundaries are not reassembled into
  logical packets — you get raw page bodies.

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-ogg
smlpkg sync
```

Reference from your `.mlb`:

```
lib/github.com/sjqtentacles/sml-ogg/ogg.mlb
```

## Building and testing

```sh
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make clean
```

## Project layout

```
sml.pkg
Makefile
lib/github.com/sjqtentacles/sml-ogg/
  ogg.sig
  ogg.sml      OggS page scanning + lacing-table segmentation
  ogg.mlb
test/
  test.sml     capture pattern, multi-page parse, no-pattern case
```

## License

MIT. See [LICENSE](LICENSE).
