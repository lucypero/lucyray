package main

import "core:fmt"
import "core:os"
import "core:io"
import "core:strings"
import "core:math/linalg"

WIDTH :: 256
HEIGHT :: 256

v3 :: [3]f32
mag :: linalg.vector_length

main :: proc() {

	sb := strings.builder_make()

	fmt.sbprintf(&sb, "P3\n%v %v\n255\n", WIDTH, HEIGHT)


	for j:= 0; j < HEIGHT ; j += 1 {

		fmt.printfln("Scanlines remaining: %v", HEIGHT - j)

		for i:= 0; i < WIDTH ; i+= 1 {

			r := f32(i) / cast(f32)(WIDTH - 1)
			g := f32(j) / cast(f32)(HEIGHT - 1)
			b :f32

			ir := int(255.999 * r) 
			ig := int(255.999 * g)
			ib := int(255.999 * b)

			fmt.sbprintf(&sb, "%v %v %v\n", ir, ig, ib)
			
		}
	}

	fmt.printfln("Done.")

	
	linalg.vector_length()

	err := os.write_entire_file_from_string("image.ppm", strings.to_string(sb))
	assert(err == os.General_Error.None)
}
