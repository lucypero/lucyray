package lucyray

TRACY_ENABLE :: #config(TRACY_ENABLE, false)

import "core:sync"
import "core:thread"
import "core:strconv"
import "core:mem"
import "core:slice"
import "core:fmt"
import mv "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:math/linalg"
import "core:math"
import "core:math/rand"
import "core:time"
import stbi "vendor:stb/image"
import tracy "../../third_party/odin-tracy"

INFINITY :: math.INF_F32
PI :: math.PI
COLOR_SKY : Color : {0.70, 0.80, 1.00}
SCENE_SELECT_DEFAULT :: 0

v2i :: [2]int
v3 :: [3]f32
point3 :: v3
Color :: v3

get_scene_select :: proc() -> uint {
	args := &os.args
	if len(args) < 2 do return SCENE_SELECT_DEFAULT
	return strconv.parse_uint(args[1], 10) or_else SCENE_SELECT_DEFAULT
}

main :: proc() {
	tracy.SetThreadName("main")
	time_start := time.now()
	switch get_scene_select() {
	case 0: do_scene_bouncing_balls()
	case 1: do_scene_checkered_balls()
	case 2: do_scene_earth()
	case 3: do_scene_perlin_spheres()
	case 4: do_scene_quads()
	case 5: do_scene_simple_light()
	case 6: do_scene_cornell_box()
	case 7: do_scene_cornell_smoke()
	case 8: do_final_scene(400, 200, 5)
	case 9: do_final_scene(800, 1000, 10)
	case: panic("scene does not exist. choose another number.")
	}
	time_after := time.now()
	fmt.printfln("Took %v", time.diff(time_start, time_after))
}

do_final_scene :: proc(image_width, samples_per_pixel, max_depth: int) {

	// Ground made up of green boxes
	mat_ground : Material = Mat_Lambertian{Color{0.48,0.83,0.53}}


	boxes_per_side : int = 20

	boxes := HittableList {
		objects = make([dynamic]Hittable)
	}

	for i in 0..<boxes_per_side {
		for j in 0..<boxes_per_side {

			i_f := cast(f32)i
			j_f := cast(f32)j

			w : f32 = 100.0
			x0 : f32 = -1000 + i_f * w
			z0 : f32 = -100.0 + j_f * w
			y0 : f32 = 0
			x1 : f32 = x0 + w
			y1 : f32 = random_double_minmax(1, 101)
			z1 : f32 = z0 + w
			hittable_list_add(&boxes, box_new({x0,y0,z0}, {x1,y1,z1}, &mat_ground))
		}
	}

	world_list := make([dynamic]Hittable)

	boxes_arena := arena_new()
	append(&world_list, bvh_node_new(boxes.objects[:], &boxes_arena)^)

	// Light
	mat_light := Material(Mat_DiffuseLight{ Color{7,7,7}})
	append(&world_list, quad_new({123,554, 147}, {300,0,0}, {0,0,265}, &mat_light))

	// Moving sphere
	center1 := point3{400,400,200}
	center2 := center1 - v3{30,0,0}
	mat_sphere := Material(Mat_Lambertian{ Color{0.7,0.3,0.1}})
	append(&world_list, sphere_new_moving(Ray{origin = center1, direction = center2 - center1}, 50,  &mat_sphere))

	mat_dielectric := Material(Mat_Dielectric{ refraction_index = 1.5})

	// Fog
	boundary_2 := sphere_new_still({0,0,0}, 5000, &mat_dielectric)
	append(&world_list, constant_medium_new(&boundary_2, .0001, Color{1,1,1}))

	// Earth
	tex_earth := texture_image_new("earthmap.jpg")
	mat_earth := Material(Mat_Lambertian{&tex_earth})
	append(&world_list, sphere_new_still({400,200,400}, 100, &mat_earth))

	// ?
	boundary := sphere_new_still({360,150,145}, 70, &mat_dielectric)
	append(&world_list, boundary)
	append(&world_list, constant_medium_new(&boundary, 0.2, Color{0.2,0.4,0.9}))

	// Glassy sphere
	append(&world_list, sphere_new_still({260,150,45}, 50, &mat_dielectric))

	// ?
	tex_per := texture_noise_new(0.2)
	mat_per := Material(Mat_Lambertian{ &tex_per})
	append(&world_list, sphere_new_still({220,280,300}, 80, &mat_per))

	// Metal sphere (not sure which one it is)
	mat_metal := Material(Mat_Metal{Color{.8,.8,.9}, 1.0})
	append(&world_list, sphere_new_still({0,150,145}, 50, &mat_metal))

	// Box made up of spheres
	boxes2 := HittableList {
		objects = make([dynamic]Hittable)
	}
	mat_white := Material(Mat_Lambertian{Color{0.73,.73,.73}})
	for _ in 0..<1000 {
		hittable_list_add(&boxes2, sphere_new_still(v3_random(0,165), 10, &mat_white))
	}

	arena := arena_new()
	bvh := bvh_node_new(boxes2.objects[:], &arena)
	bvh_rotate := rotate_new(bvh, 15)
	bvh_translate := translate_new(&bvh_rotate, {-100,270,395})
	append(&world_list, bvh_translate)

	// Render
	cam := camera_init(Camera{

		aspect_ratio = 1.0,

		// frame quality
		image_width = image_width,
		samples_per_pixel = samples_per_pixel,
		max_depth = max_depth,

		// camera parameters
		vfov = 40,

		lookfrom = {478,278,-600},
		lookat = {278,278,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = {0,0,0},
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_cornell_smoke :: proc() {
	world_list := make([dynamic]Hittable)

	mat_red := Material(Mat_Lambertian{ Color{.65,.05,.05}})
	mat_white := Material(Mat_Lambertian{ Color{.73, .73, .73}})
	mat_green := Material(Mat_Lambertian{ Color{.12, .45, .15}})
	mat_light := Material(Mat_DiffuseLight{ Color{7,7,7}})

	// Light
	append(&world_list, quad_new({113,554,127}, {330,0,0}, {0,0,305}, &mat_light))

	// Walls
	append(&world_list, quad_new({555,0,0}, {0,555,0}, {0,0,555}, &mat_green))
	append(&world_list, quad_new({0,0,0}, {0,555,0}, {0,0,555}, &mat_red))
	append(&world_list, quad_new({0,0,0}, {555,0,0}, {0,0,555}, &mat_white))

	// Ceiling
	append(&world_list, quad_new({555,555,555}, {-555,0,0}, {0,0,-555}, &mat_white))

	// Floor
	append(&world_list, quad_new({0,0,555}, {555,0,0}, {0,555,0}, &mat_white))

	{
		box := new_clone(box_new(point3{0,0,0}, point3{165,330,165}, &mat_white))
		box_rotated := new_clone(rotate_new(box, 15))
		box_translated := new_clone(translate_new(box_rotated, {265,0,295}))
		append(&world_list, constant_medium_new(box_translated, 0.01, Color{0,0,0}))
	}

	{
		box := new_clone(box_new(point3{0,0,0}, point3{165,165,165}, &mat_white))
		box_rotated := new_clone(rotate_new(box, -18))
		box_translated := new_clone(translate_new(box_rotated, {130,0,65}))
		append(&world_list, constant_medium_new(box_translated, 0.01, Color{1,1,1}))
	}

	cam := camera_init(Camera{

		aspect_ratio = 1.0,

		// frame quality
		image_width = 600,
		samples_per_pixel = 200,
		max_depth = 50,

		// camera parameters
		vfov = 40,

		lookfrom = {278, 278, -800},
		lookat = {278, 278, 0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = {0,0,0},
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_cornell_box :: proc() {
	world_list := make([dynamic]Hittable)

	mat_red := Material(Mat_Lambertian{ Color{.65,.05,.05}})
	mat_white := Material(Mat_Lambertian{ Color{.73, .73, .73}})
	mat_green := Material(Mat_Lambertian{ Color{.12, .45, .15}})

	mat_light := Material(Mat_DiffuseLight{ Color{15,15,15}})

	// Light
	append(&world_list, quad_new({343, 554, 332}, {-130, 0, 0}, {0, 0, -105}, &mat_light))

	// Walls
	append(&world_list, quad_new({555,0,0}, {0,555,0}, {0,0,555}, &mat_green))
	append(&world_list, quad_new({0,0,0}, {0,555,0}, {0,0,555}, &mat_red))
	append(&world_list, quad_new({0,0,0}, {555,0,0}, {0,0,555}, &mat_white))

	// Ceiling
	append(&world_list, quad_new({555,555,555}, {-555,0,0}, {0,0,-555}, &mat_white))

	// Floor
	append(&world_list, quad_new({0,0,555}, {555,0,0}, {0,555,0}, &mat_white))

	{
		box := new_clone(box_new(point3{0,0,0}, point3{165,330,165}, &mat_white))
		box_rotated := new_clone(rotate_new(box, 15))
		append(&world_list, translate_new(box_rotated, {265,0,295}))
	}

	{
		box := new_clone(box_new(point3{0,0,0}, point3{165,165,165}, &mat_white))
		box_rotated := new_clone(rotate_new(box, -18))
		append(&world_list, translate_new(box_rotated, {130,0,65}))
	}

	cam := camera_init(Camera{

		aspect_ratio = 1.0,

		// frame quality
		image_width = 200,
		samples_per_pixel = 50,
		max_depth = 50,

		// camera parameters
		vfov = 40,

		lookfrom = {278, 278, -800},
		lookat = {278, 278, 0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = {0,0,0},
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

// Adds 6 quads that contains the two opposite vertices a & b, to a hittable list
box_new :: proc(a, b: point3, mat: ^Material) -> Hittable {
	min := point3{min(a.x,b.x), min(a.y,b.y), min(a.z,b.z)}
	max := point3{max(a.x,b.x), max(a.y,b.y), max(a.z,b.z)}

	dx := v3{max.x - min.x, 0, 0}
	dy := v3{0, max.y - min.y,0}
	dz := v3{0,0,max.z-min.z}

	hlist := HittableList {
		objects = make([dynamic]Hittable, 0, 6)
	}

	hittable_list_add(&hlist, quad_new(point3{min.x, min.y, max.z}, dx, dy, mat)) // front
	hittable_list_add(&hlist, quad_new(point3{max.x,min.y,max.z}, -dz, dy, mat)) // right
	hittable_list_add(&hlist, quad_new(point3{max.x, min.y, min.z}, -dx, dy, mat)) // back
	hittable_list_add(&hlist, quad_new(point3{min.x,min.y,min.z}, dz, dy, mat)) // left
	hittable_list_add(&hlist, quad_new(point3{min.x,max.y,max.z}, dx, -dz, mat)) // top
	hittable_list_add(&hlist, quad_new(point3{min.x, min.y, min.z}, dx, dz, mat)) // bottom

	return hlist
}

do_scene_simple_light :: proc() {
	world_list := make([dynamic]Hittable)

	tex_per := texture_noise_new(4)
	mat_per := Material(Mat_Lambertian{ &tex_per})

	append(&world_list, sphere_new_still({0, -1000, 0}, 1000, &mat_per))
	append(&world_list, sphere_new_still({0,2,0}, 2, &mat_per))

	mat_diffuse_light := Material(Mat_DiffuseLight{ Color{4,4,4}})

	append(&world_list, sphere_new_still({0,7,0}, 2, &mat_diffuse_light))
	append(&world_list, quad_new({3,1,-2}, {2,0,0}, {0,2,0}, &mat_diffuse_light))

	cam := camera_init(Camera{

		aspect_ratio = 16.0 / 9.0,

		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {26, 3, 6},
		lookat = {0,2,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = {0,0,0}
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_quads :: proc() {
	world_list := make([dynamic]Hittable)


	mat_left_red := Material(Mat_Lambertian{Color{1,0.2,0.2}})
	mat_back_green := Material(Mat_Lambertian{Color{0.2,1.0,0.2}})
	mat_right_blue := Material(Mat_Lambertian{Color{0.2,0.2,1.0}})
	mat_upper_orange := Material(Mat_Lambertian{Color{1.0, 0.5, 0.0}})
	mat_lower_teal := Material(Mat_Lambertian{Color{0.2,0.8,0.8}})

	append(&world_list, quad_new({-3,-2,5}, {0, 0, -4}, {0, 4, 0}, &mat_left_red))
	append(&world_list, quad_new({-2,-2,0}, {4, 0, 0}, {0, 4, 0}, &mat_back_green))
	append(&world_list, quad_new({3,-2,1}, {0, 0, 4}, {0, 4, 0}, &mat_right_blue))
	append(&world_list, quad_new({-2,3,1}, {4,0,0}, {0,0,4}, &mat_upper_orange))
	append(&world_list, quad_new({-2,-3,5}, {4,0,0}, {0,0,-4}, &mat_lower_teal))

	cam := camera_init(Camera{

		aspect_ratio = 1.0,

		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 80,

		lookfrom = {0,0,9},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = COLOR_SKY
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_perlin_spheres :: proc() {
	world_list := make([dynamic]Hittable)

	tex_perlin := texture_noise_new(4)
	mat_perlin := Material(Mat_Lambertian{ &tex_perlin})

	append(&world_list, sphere_new_still({0,-1000,0}, 1000, &mat_perlin))
	append(&world_list, sphere_new_still({0,2,0}, 2, &mat_perlin))

	cam := camera_init(Camera{

		// aspect_ratio = 16.0 / 9.0,

		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {13,2,3},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,
		color_background = COLOR_SKY
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_earth :: proc() {
	world_list := make([dynamic]Hittable)

	tex_earth := texture_image_new("earthmap.jpg")
	mat_earth := Material(Mat_Lambertian{ &tex_earth})

	append(&world_list, sphere_new_still({0,0,0}, 2, &mat_earth))

	cam := camera_init(Camera{
		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {0, 0, 12},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,

		color_background = COLOR_SKY
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_checkered_balls :: proc() {

	world_list := make([dynamic]Hittable)

	tex_white := Texture(TextureSolid{Color{.9,.9,.9}})
	tex_black := Texture(TextureSolid{Color{.2,.3,.1}})
	tex_checker := Texture(TextureCheckered{1 / 0.32, &tex_white, &tex_black})

	mat_checkered := Material(Mat_Lambertian{ &tex_checker})

	append(&world_list, sphere_new_still({0,-10,0}, 10, &mat_checkered))
	append(&world_list, sphere_new_still({0,10,0}, 10, &mat_checkered))

	cam := camera_init(Camera{
		// frame quality
		image_width = 400,
		samples_per_pixel = 100,
		max_depth = 50,

		// camera parameters
		vfov = 20,

		lookfrom = {13,2,3},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0,
		focus_dist = 10,
		color_background = COLOR_SKY
	})

	bvh_arena := arena_new()
	world := bvh_node_new(world_list[:], &bvh_arena)
	camera_render(&cam, world^)
}

do_scene_bouncing_balls :: proc() {
	bvh_arena := arena_new()

	world := make([dynamic]Hittable, 0, 20, allocator = context.temp_allocator)

	material_ground := Material(Mat_Lambertian{Color{0.5,0.5,0.5}})
	append(&world, sphere_new_still({ 0.0, -1000, 0}, 1000.0, &material_ground))

	for a := -11; a < 11 ; a+=1 {
		for b := -11; b < 11; b+=1 {
			choose_mat := random_double()
			center := v3{f32(a) + 0.9*random_double(), 0.2, f32(b) + 0.9*random_double()}

			if (linalg.length(center - point3{4, 0.2, 0}) > 0.9) {
				sphere_material, m_err  := mv.new(&bvh_arena, Material)
				ensure(m_err == .None)

				if (choose_mat < 0.8) {
					// diffuse
					albedo : Color = v3_random_range(0, 1) * v3_random_range(0, 1)
					sphere_material^ = Material(Mat_Lambertian{albedo})
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{origin = center, direction = center2 - center}, 0.2, sphere_material))
				} else if (choose_mat < 0.95) {
					// metal
					albedo : Color = v3_random_range(0.5, 1)
					fuzz := random_double(0, 0.5)
					sphere_material^ = Material(Mat_Metal{ albedo, fuzz})
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{origin = center, direction = center2 - center}, 0.2, sphere_material))
				} else {
					// glass
					sphere_material^ = Material(Mat_Dielectric{ refraction_index = 1.5})
					center2 := center + v3{0, random_double(0,.5), 0}
					append(&world, sphere_new_moving(Ray{origin = center, direction = center2 - center}, 0.2, sphere_material))
				}
			}
		}
	}

	material1 := Material(Mat_Dielectric{ refraction_index = 1.5})
	append(&world, sphere_new_still({0,1,0}, 1, &material1))

	material2 := Material(Mat_Lambertian{ Color{0.4,0.2,0.1}})
	append(&world, sphere_new_still({-4,1,0}, 1, &material2))

	material3 := Material(Mat_Metal{ Color{0.7, 0.6, 0.5}, 0})
	append(&world, sphere_new_still({4,1,0}, 1, &material3))


	world_opt := bvh_node_new(world[:], &bvh_arena)
	free_all(context.temp_allocator)

	cam := camera_init(Camera{
		// frame quality
		image_width = 400,
		samples_per_pixel = 200,
		max_depth = 10,

		// camera parameters
		vfov = 20,

		lookfrom = {13,2,3},
		lookat = {0,0,0},
		vup = {0,1,0},

		defocus_angle = 0.6,
		focus_dist = 10,
		color_background = COLOR_SKY
	})

	camera_render(&cam, world_opt^)
}

Ray :: struct {
	origin: point3,
	direction: v3,
	time:f32
}

ray_at :: proc(r: Ray, t: f32) -> point3 {
	return r.origin + t * r.direction
}

write_color :: proc(sb: ^strings.Builder, pixel_color: Color) {
	// Translate the [0,1] component values to the byte range [0,255].
	intensity := Interval{0, 0.999}

	// Apply a linear to gamma transform for gamma 2
	r := linear_to_gamma(pixel_color.r)
	g := linear_to_gamma(pixel_color.g)
	b := linear_to_gamma(pixel_color.b)

	rbyte := cast(int)(256 * interval_clamp(intensity, r))
	gbyte := cast(int)(256 * interval_clamp(intensity, g))
	bbyte := cast(int)(256 * interval_clamp(intensity, b))

	fmt.sbprintf(sb, "%v %v %v\n", rbyte, gbyte, bbyte)
}


HitRecord :: struct {
	p: point3,
	mat: ^Material,
	normal: v3,
	t: f32,
	u, v: f32,
	front_face: bool
}

// Sets the hit record normal vector.
// NOTE: the parameter `outward_normal` is assumed to have unit length.
hr_set_face_normal :: proc(hr: ^HitRecord, r: Ray, outward_normal: v3) {
	hr.front_face = linalg.dot(r.direction, outward_normal) < 0
	hr.normal = hr.front_face ? outward_normal : -outward_normal
}

Hittable :: union #no_nil {
	Sphere,
	AABB,
	BVH_Node,
	Quad,
	Translate,
	Rotate_Y,
	HittableList,
	ConstantMedium
}

hittable_get_bounding_box :: proc(hittable: Hittable) -> AABB {
	switch inner in hittable {
	case Sphere: return inner.bbox
	case AABB: return inner
	case BVH_Node: return inner.bbox
	case Quad: return inner.bbox
	case Translate: return inner.bbox
	case Rotate_Y: return inner.bbox
	case HittableList: return inner.bbox
	case ConstantMedium: return hittable_get_bounding_box(inner.boundary^)
	case: panic("cannot reach here")
	}
}

hittable_hit :: proc(hittable: Hittable, r: Ray, ray_t: Interval) -> (bool, HitRecord) {
	switch inner in hittable {
	case Sphere: return sphere_hit(inner, r, ray_t)
	case AABB: return aabb_hit(inner, r, ray_t)
	case BVH_Node: return bvh_node_hit(inner, r, ray_t)
	case Quad:  return quad_hit(inner, r, ray_t)
	case Translate: return translate_hit(inner, r, ray_t)
	case Rotate_Y: return rotate_hit(inner, r, ray_t)
	case HittableList: return hittable_list_hit(inner, r, ray_t)
	case ConstantMedium: return constant_medium_hit(inner, r, ray_t)
	case: panic("unsupported shape")
	}
}

Sphere :: struct {
	center: Ray,
	radius: f32,
	mat: ^Material,
	bbox: AABB
}

// inits a sphere that is standing still
sphere_new_still :: proc(orig: v3, rad: f32, mat: ^Material) -> Hittable {
	// calculating bbox
	rvec := v3{rad, rad, rad}
	bbox := aabb_new(orig - rvec, orig + rvec)
	return Sphere{Ray{origin = orig}, rad, mat, bbox}
}

sphere_new_moving :: proc(center: Ray, rad: f32, mat: ^Material) -> Sphere {
	// calculating bbox
	rvec := v3{rad, rad, rad}
	box1 := aabb_new(ray_at(center, 0) - rvec, ray_at(center, 0) + rvec)
	box2 := aabb_new(ray_at(center, 1) - rvec, ray_at(center, 1) + rvec)
	bbox := aabb_union(box1, box2)
	return Sphere{center, rad, mat, bbox}
}

sphere_hit :: proc(sphere: Sphere, r: Ray, ray_t: Interval) -> (hit: bool, rec: HitRecord) {
	current_center := ray_at(sphere.center, r.time)
	oc := current_center - r.origin

	a := linalg.length2(r.direction)
	h := linalg.dot(r.direction, oc)
	c := linalg.length2(oc) - (sphere.radius * sphere.radius)

	discriminant := h*h - a*c

	if discriminant < 0 do return false, {}

	sqrtd := linalg.sqrt(discriminant)

	// // Find the nearest root that lies in the acceptable range.
	root := (h - sqrtd) / a

	if !interval_surrounds(ray_t, root) {
		root = (h + sqrtd) / a
		if !interval_surrounds(ray_t, root) do return false, {}
	}

	rec.t = root
	rec.p = ray_at(r, rec.t)
	rec.mat = sphere.mat
	outward_normal := (rec.p - current_center) / sphere.radius
	hr_set_face_normal(&rec, r, outward_normal)
	u, v := sphere_get_uv(sphere, outward_normal)
	rec.u = u
	rec.v = v
	return true, rec
}

// p: a given point on the sphere of radius one, centered at the origin.
// u: returned value [0,1] of angle around the Y axis from X=-1.
// v: returned value [0,1] of angle from Y=-1 to Y=+1.
//     <1 0 0> yields <0.50 0.50>       <-1  0  0> yields <0.00 0.50>
//     <0 1 0> yields <0.50 1.00>       < 0 -1  0> yields <0.50 0.00>
//     <0 0 1> yields <0.25 0.50>       < 0  0 -1> yields <0.75 0.50>
sphere_get_uv :: proc(sph: Sphere, p: point3) -> (u, v: f32) {
	theta := math.acos(-p.y)
	phi := math.atan2(-p.z, p.x) + PI

	u = phi / (2*PI)
	v = theta / PI

	return
}

hit_list :: proc(hittables: []Hittable, r: Ray, interval: Interval) -> (bool, HitRecord) {
	temp_rec : HitRecord
	hit_anything: bool
	closest_so_far := interval.max

	for hittable in hittables {
		did_hit, rec := hittable_hit(hittable, r, {interval.min, closest_so_far})
		if did_hit {
			hit_anything = true
			closest_so_far = rec.t
			temp_rec = rec
		}
	}

	return hit_anything, temp_rec
}


degrees_to_radians :: proc(degrees: f32) -> f32 {
	return degrees * PI / 180
}

Interval :: struct {
	min, max: f32
}

interval_offset :: proc(interval: Interval, displacement: f32) -> Interval {
	return Interval{interval.min + displacement, interval.max + displacement}
}

interval_size :: proc(i : Interval) -> f32 {
	return abs(i.max - i.min)
}

interval_expand :: proc(int: Interval, delta: f32) -> Interval {
	padding := delta / 2
	return Interval{int.min - padding, int.max + padding}
}

interval_contains :: proc(i: Interval, x: f32) -> bool {
	return i.min <= x && x <= i.max
}

interval_surrounds :: proc(i: Interval, x: f32) -> bool {
	return i.min < x && x < i.max
}

interval_clamp :: proc(i: Interval, x: f32) -> f32 {
	return clamp(x, i.min, i.max)
}

// Create the interval tightly enclosing the two input intervals.
interval_union :: proc(a, b: Interval) -> Interval {
	return Interval {
		a.min <= b.min ? a.min : b.min,
		a.max >= b.max ? a.max : b.max
	}
}

@rodata
interval_empty := Interval{+INFINITY, -INFINITY}

@rodata
interval_universe := Interval{-INFINITY, +INFINITY}

Camera :: struct {

	// Public
	image_width: int,

	aspect_ratio : f32,

	samples_per_pixel: int, // Count of random samples for each pixel
	max_depth: int,
	vfov: f32, // vertical view angle (field of view)

	lookfrom : point3,   // Point camera is looking from
	lookat   :point3,  // Point camera is looking at
	vup      :v3,     // Camera-relative "up" direction

	defocus_angle :f32,  // Variation angle of rays through each pixel
	focus_dist :f32,    // Distance from camera lookfrom point to plane of perfect focus
	color_background: Color,

	// Private
	pixel_samples_scale: f32, // Color scale factor for a sum of pixel samples
	sb: strings.Builder,
	pixel00_loc : point3,
	image_height: int,
	center: point3,
	pixel_delta_u : v3,
	pixel_delta_v : v3,
	u,v,w: v3,

	defocus_disk_u, defocus_disk_v: v3 // Defocus disk horizontal / vertical radius
}

camera_init :: proc(cam_init: Camera) -> (cam: Camera) {

	cam = cam_init

	if cam.aspect_ratio == 0 do cam.aspect_ratio = 16.0 / 9.0

	cam.center = cam.lookfrom

	cam.sb = strings.builder_make()
	cam.pixel_samples_scale = 1 / cast(f32)cam.samples_per_pixel

	cam.image_height = max(1, cast(int)(cast(f32)cam.image_width / cam.aspect_ratio))

	// Determine viewport dimensions.
	theta := degrees_to_radians(cam.vfov)
	h := linalg.tan(theta/2)
	viewport_height := 2 * h * cam.focus_dist
	viewport_width : f32 = viewport_height * (cast(f32)cam.image_width / cast(f32)cam.image_height)

	// Calculate the u,v,w unit basis vectors for the camera coordinate frame.
	cam.w = linalg.normalize(cam.lookfrom - cam.lookat)
	cam.u = linalg.normalize(linalg.cross(cam.vup, cam.w))
	cam.v = linalg.cross(cam.w, cam.u)

	// Calculate the vectors across the horizontal and down the vertical viewport edges.
	viewport_u := viewport_width * cam.u // Vector across viewport horizontal edge
	viewport_v := viewport_height * -cam.v // Vector down viewport vertical edge

	// Calculate the horizontal and vertical delta vectors from pixel to pixel.
	cam.pixel_delta_u = viewport_u / cast(f32)cam.image_width
	cam.pixel_delta_v = viewport_v / cast(f32)cam.image_height

	// Calculate the location of the upper left pixel.
	viewport_upper_left : point3 = cam.center - (cam.focus_dist * cam.w) - viewport_u / 2 - viewport_v / 2
	cam.pixel00_loc = viewport_upper_left + 0.5 * (cam.pixel_delta_u + cam.pixel_delta_v)

	// Calculate the camera defocus disk basis vectors.
	defocus_radius := cam.focus_dist * linalg.tan(degrees_to_radians(cam.defocus_angle / 2))
	cam.defocus_disk_u = cam.u * defocus_radius
	cam.defocus_disk_v = cam.v * defocus_radius

	return cam
}

camera_defocus_disk_sample :: proc(cam: Camera) -> v3{
	// Returns a random point in the camera defocus disk.
	p := random_in_unit_disk()
	return cam.center + (p[0] * cam.defocus_disk_u) + (p[1] * cam.defocus_disk_v)
}

g_cam: Camera
g_out_buffer: []Color
g_world: Hittable
g_tile_width: int
g_tile_counter: int
g_tile_total: int
g_tile_x_count: int
g_tile_y_count: int

camera_render :: proc(cam: ^Camera, world: Hittable) {
	g_out_buffer = make([]Color, cam.image_width * cam.image_height)
	g_cam = cam^
	g_world = world

	g_tile_width = 32
	g_tile_x_count = cam.image_width / g_tile_width
	g_tile_y_count = cam.image_height / g_tile_width
	if cam.image_width % g_tile_width != 0 do g_tile_x_count += 1
	if cam.image_height % g_tile_width != 0 do g_tile_y_count += 1
	g_tile_total = g_tile_x_count * g_tile_y_count


	ThreadData :: struct {
		in_tid: int,
		out_time_spent: time.Duration
	}

	thread_main :: proc(data: rawptr) {
		time_start := time.now()
		tdata := cast(^ThreadData)data
		ar := arena_new()
		context.temp_allocator = mv.arena_allocator(&ar)

		for {


			tile_i := sync.atomic_add(&g_tile_counter, 1)
			if tile_i > g_tile_total do break

			when TRACY_ENABLE {
			tile_zone_tag := fmt.tprintf("Zone %v/%v", tile_i, g_tile_total)
			tracy.ZoneN(tile_zone_tag);
			}



			x_start := (tile_i % g_tile_x_count) * g_tile_width
			y_start := (tile_i / g_tile_x_count) * g_tile_width

			// prob and off by one error here
			x_end := min(x_start + g_tile_width, g_cam.image_width)
			y_end := min(y_start + g_tile_width, g_cam.image_height)

			for y in y_start..<y_end {
				for x in x_start..<x_end {
					pixel_color : Color 
					for _ in 0 ..< g_cam.samples_per_pixel {
						r: Ray = camera_get_ray(g_cam, x, y)
						pixel_color += camera_ray_color(g_cam, r, g_cam.max_depth, g_world)
					}
					g_out_buffer[y * g_cam.image_width + x] = g_cam.pixel_samples_scale * pixel_color
				}
			}

			fmt.printfln("Tiles Rendered: %v/%v", tile_i, g_tile_total)
		}

		time_end := time.now()
		tdata.out_time_spent = time.diff(time_start, time_end)
	}

	thread_count := os.get_processor_core_count()
	threads := make([]^thread.Thread, thread_count)

	tdata := make([]ThreadData, thread_count)

	for &t, i in threads {
		tdata[i].in_tid = i
		t = thread.create_and_start_with_data(&tdata[i], thread_main)
	}

	thread.join_multiple(..threads)

	for &t in threads {
		thread.destroy(t)
	}

	tmin : time.Duration = time.MAX_DURATION
	tmax : time.Duration = time.MIN_DURATION

	for data in tdata {
		if data.out_time_spent < tmin do tmin = data.out_time_spent
		if data.out_time_spent > tmax do tmax = data.out_time_spent
	}

	fmt.printfln("Thread timing delta: [%v,%v], magnitude: %v", tmin, tmax, tmax-tmin)

	// Writing Image File

	fmt.sbprintf(&cam.sb, "P3\n%v %v\n255\n", cam.image_width, cam.image_height)

	for pixel in 0..<cam.image_width * cam.image_height {
		write_color(&cam.sb, g_out_buffer[pixel])
	}

	// linalg.vector_length()
	err := os.write_entire_file_from_string("image.ppm", strings.to_string(cam.sb))
	assert(err == os.General_Error.None)

	strings.builder_reset(&cam.sb)
}

camera_ray_color :: proc(cam: Camera, r: Ray, depth: int, world: Hittable) -> Color {


	// If we've exceeded the ray bounce limit, no more light is gathered.
	if depth <= 0 do return Color{0,0,0}

	// passing a limig min w a small number to avoid shadow acne
	hit, rec := hittable_hit(world, r, {0.001, INFINITY})

	// If we've hit nothing, we return the camera background color.
	if !hit {
		return cam.color_background
	}

	color_attenuation, ray_scatter, did_scatter := material_scatter(rec.mat^, r, rec)
	color_from_emission : Color = material_emitted(rec.mat^, rec.u, rec.v, rec.p)

	// If the ray doesn't scatter against the material, return the emission color.
	if !did_scatter {
		return color_from_emission
	} 	

	color_from_scatter : Color = color_attenuation * camera_ray_color(cam, ray_scatter, depth - 1, world)
	return color_from_emission + color_from_scatter
}

linear_to_gamma :: proc(linear_component: f32) -> f32 {
	if linear_component > 0 do return linalg.sqrt(linear_component)
	return 0
}

// Construct a camera ray originating from the origin and directed at randomly sampled
// point around the pixel location i, j.
camera_get_ray :: proc(cam: Camera, i, j: int) -> Ray {

	offset := sample_square()
	pixel_sample := cam.pixel00_loc +
	((f32(i) + offset.x) * cam.pixel_delta_u) +
	((f32(j) + offset.y) * cam.pixel_delta_v)

	ray_origin := (cam.defocus_angle <= 0) ? cam.center : camera_defocus_disk_sample(cam)
	ray_direction := pixel_sample - ray_origin
	ray_time := random_double()

	return Ray{ray_origin, ray_direction, ray_time}
}

// Returns the vector to a random point in the [-.5,-.5]-[+.5,+.5] unit square.
sample_square :: proc() -> v3 {
	return v3{random_double() - 0.5, random_double() - 0.5, 0}
}

// Returns a random real in [0,1).
random_double_norm :: proc() -> f32 {
	return rand.float32()
}

// Returns a random real in [min,max).
random_double_minmax :: proc(min, max: f32) -> f32 {
	return rand.float32_range(min, max)
}

random_double :: proc{random_double_norm, random_double_minmax}

random_int :: proc(min, max: int) -> int {
	return rand.int_range(min, max)
}

random_in_unit_disk :: proc() -> v3 {
	for {
		p := v3{random_double(-1,1), random_double(-1,1), 0}
		if (linalg.length2(p) < 1) {
			return p
		}
	}
}

v3_random_one :: proc () -> v3 {
	return v3{random_double(), random_double(), random_double()}
}

v3_random_range :: proc(min, max: f32) -> v3 {
	return v3{random_double(min,max), random_double(min,max), random_double(min,max)}
}

v3_random :: proc{v3_random_one, v3_random_range}

v3_random_unit_vector :: proc() -> v3 {
	for {
		p := v3_random(-1,1)
		lensq := linalg.length2(p)
		if (1e-160 < lensq && lensq <= 1) do return p / linalg.sqrt(lensq)
	}
}

v3_is_near_zero :: proc(v: v3) -> bool {
	s : f32 = 1e-8
	return abs(v.x) < s && (abs(v.y) < s) && (abs(v.z) < s)
}

v3_reflect :: proc(v: v3, n: v3) -> v3 {
	return v - 2*linalg.dot(v,n)*n
}

v3_refract :: proc(uv: v3, n: v3, etai_over_etat : f32) -> v3 {
	cos_theta := min(linalg.dot(-uv, n), 1.0)
	r_out_perp : v3 = etai_over_etat * (uv + cos_theta*n)
	r_out_parallel : v3 = -linalg.sqrt(abs(1.0 - linalg.length2(r_out_perp))) * n
	return r_out_perp + r_out_parallel
}

random_on_hemisphere :: proc(normal: v3) -> v3 {
	on_unit_sphere := v3_random_unit_vector()
	// In the same hemisphere as the normal
	if linalg.dot(on_unit_sphere, normal) > 0 do return on_unit_sphere
	return -on_unit_sphere
}

Mat_Lambertian :: struct {tex: TextureOrColor}
Mat_Metal :: struct {tex: TextureOrColor, fuzz: f32}
Mat_Dielectric :: struct {refraction_index:f32}
Mat_DiffuseLight :: struct {tex: TextureOrColor}
Mat_Isotropic :: struct {tex: TextureOrColor}

Material :: union #no_nil { Mat_Lambertian, Mat_Metal, Mat_Dielectric, Mat_DiffuseLight, Mat_Isotropic }

reflectance :: proc(cosine: f32, refraction_index: f32) -> f32 {
	// Use Schlick's approximation for reflectance.
	r0 := (1 - refraction_index) / (1 + refraction_index)
	r0 = r0*r0
	return r0 + (1-r0)*linalg.pow((1 - cosine),5)
}

material_scatter :: proc(mat:Material, ray_in: Ray, rec: HitRecord) -> (col_attenuation: Color, ray_scattered: Ray, did_scatter: bool) {

	did_scatter = true

	switch m_inner in mat {
	case Mat_Lambertian:
		scatter_direction := rec.normal + v3_random_unit_vector()

		if v3_is_near_zero(scatter_direction) {
			scatter_direction = rec.normal
		}

		ray_scattered = Ray{rec.p, scatter_direction, ray_in.time}
		col_attenuation = texture_or_color_sample(m_inner.tex, rec.u, rec.v, rec.p)
		return
	case Mat_Metal:
		reflected := v3_reflect(ray_in.direction, rec.normal)
		reflected = linalg.normalize(reflected) + (m_inner.fuzz * v3_random_unit_vector())
		ray_scattered = Ray{rec.p, reflected, ray_in.time}
		col_attenuation = texture_or_color_sample(m_inner.tex, rec.u, rec.v, rec.p)
		did_scatter = linalg.dot(ray_scattered.direction, rec.normal) > 0
		return
	case Mat_Dielectric:
		col_attenuation = Color{1.0, 1.0, 1.0}
		ri : f32 = rec.front_face ? (1.0/m_inner.refraction_index) : m_inner.refraction_index
		unit_direction : v3 = linalg.normalize(ray_in.direction)

		cos_theta : f32 = min(linalg.dot(-unit_direction, rec.normal), 1.0)
		sin_theta : f32 = linalg.sqrt(1.0 - cos_theta*cos_theta)

		cannot_refract : bool = ri * sin_theta > 1.0
		direction: v3

		if (cannot_refract || reflectance(cos_theta, ri) > random_double()) {
			direction = v3_reflect(unit_direction, rec.normal)
		} else {
			direction = v3_refract(unit_direction, rec.normal, ri)
		}

		ray_scattered = Ray{rec.p, direction, ray_in.time}
	case Mat_DiffuseLight:
		return {}, {}, false
	case Mat_Isotropic:
		ray_scattered = Ray{rec.p, v3_random_unit_vector(), ray_in.time}
		col_attenuation = texture_or_color_sample(m_inner.tex, rec.u, rec.v, rec.p)
	}

	return
}

material_emitted :: proc(mat:Material, u, v: f32, p: point3) -> (col: Color) {
	switch m_inner in mat {
	case Mat_DiffuseLight:
		return texture_or_color_sample(m_inner.tex, u,v,p)
	case Mat_Lambertian:
	case Mat_Metal:
	case Mat_Dielectric:
	case Mat_Isotropic:
		return {0,0,0}
	}
	return
}


AABB :: struct {
	x, y, z: Interval
}

// Adjust the AABB so that no side is narrower than some delta, padding if necessary.
aabb_pad_to_minimums :: proc(aabb: ^AABB) {
	delta :: 0.0001
	if interval_size(aabb.x) < delta do aabb.x = interval_expand(aabb.x, delta)
	if interval_size(aabb.y) < delta do aabb.y = interval_expand(aabb.y, delta)
	if interval_size(aabb.z) < delta do aabb.z = interval_expand(aabb.z, delta)
}

aabb_translate :: proc(aabb: AABB, offset: v3) -> AABB {
	return {
		interval_offset(aabb.x, offset.x),
		interval_offset(aabb.y, offset.y),
		interval_offset(aabb.z, offset.z)
	}
}

aabb_new_empty :: proc() -> (res: AABB) {

	res = AABB {
		x = interval_empty,
		y = interval_empty,
		z = interval_empty,
	}

	aabb_pad_to_minimums(&res)
	return
}

// Treat the two points a and b as extrema for the bounding box, so we don't require a
// particular minimum/maximum coordinate order.
aabb_new :: proc(a, b: point3) -> (res: AABB) {
	res = AABB {
		x = (a[0] <= b[0]) ? Interval{a[0], b[0]} : Interval{b[0], a[0]},
		y = (a[1] <= b[1]) ? Interval{a[1], b[1]} : Interval{b[1], a[1]},
		z = (a[2] <= b[2]) ? Interval{a[2], b[2]} : Interval{b[2], a[2]},
	}

	aabb_pad_to_minimums(&res)
	return
}

// Returns the index of the longest axis of the bounding box.
aabb_longest_axis :: proc(aabb: AABB) -> int {
	x_s := interval_size(aabb.x)
	y_s := interval_size(aabb.y)
	z_s := interval_size(aabb.z)

	if x_s > y_s {
		return x_s > z_s ? 0 : 2
	} else {
		return y_s > z_s ? 1 : 2
	}
}

// constructs a AABB that encloses two input AABBs
@(require_results)
aabb_union :: proc(box0, box1: AABB) -> AABB {
	return AABB {
		x = interval_union(box0.x, box1.x),
		y = interval_union(box0.y, box1.y),
		z = interval_union(box0.z, box1.z)
	}
}

aabb_get_axis_interval :: proc(aabb: AABB, axis_index: int) -> Interval {
	switch axis_index {
	case 0: return aabb.x
	case 1: return aabb.y
	case: return aabb.z
	}
}

aabb_hit :: #force_inline proc(aabb: AABB, r: Ray, ray_t : Interval) -> (bool, HitRecord) {

	ray_t := ray_t

	for axis in 0..<3 {

		ax := aabb_get_axis_interval(aabb, axis)

		adinv := 1.0 / r.direction[axis]

		t0 := (ax.min - r.origin[axis]) * adinv
		t1 := (ax.max - r.origin[axis]) * adinv

		if t0 < t1 {
			if t0 > ray_t.min do ray_t.min = t0
			if t1 < ray_t.max do ray_t.max = t1
		} else {
			if t1 > ray_t.min do ray_t.min = t1
			if t0 < ray_t.max do ray_t.max = t0
		}

		if (ray_t.max <= ray_t.min) {
			return false, HitRecord{}
		}
	}

	return true, HitRecord{}
}

BVH_Node :: struct {
	left, right: ^Hittable,
	bbox: AABB
}

box_compare :: proc(a, b: Hittable, axis_index: int) -> bool {
	a_axis_interval := aabb_get_axis_interval(hittable_get_bounding_box(a), axis_index)
	b_axis_interval := aabb_get_axis_interval(hittable_get_bounding_box(b), axis_index)
	return a_axis_interval.min < b_axis_interval.min
}

box_compare_x :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 0)
}

box_compare_y :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 1)
}

box_compare_z :: proc(a, b: Hittable) -> bool {
	return box_compare(a,b, 2)
}

bvh_node_new :: proc(objects: []Hittable, allocator : ^mv.Arena) -> (res_hittable: ^Hittable) {

	err : mv.Allocator_Error
	res_hittable, err = mv.new_clone(allocator, Hittable(BVH_Node{}))
	ensure(err == .None)

	res := &res_hittable.(BVH_Node)

	// Build the bounding box of the span of source objects.
	res.bbox = aabb_new_empty()

	for obj in objects {
		res.bbox = aabb_union(res.bbox, hittable_get_bounding_box(obj))
	}

	axis := aabb_longest_axis(res.bbox)

	comparator := (axis == 0) ? box_compare_x: (axis == 1) ? box_compare_y : box_compare_z

	object_span := len(objects)

	mem_err : mv.Allocator_Error

	if (object_span == 1) {
		res.left, mem_err = mv.new_clone(allocator, objects[0])
		res.right = res.left
	} else if (object_span == 2) {
		res.left, mem_err = mv.new_clone(allocator, objects[0])
		res.right, mem_err  = mv.new_clone(allocator, objects[1])
	} else {
		slice.sort_by(objects, comparator)
		mid := object_span/2
		res.left = bvh_node_new(objects[:mid], allocator)
		res.right = bvh_node_new(objects[mid:], allocator)
	}

	return
}

bvh_node_hit :: proc(bvh_node: BVH_Node, r: Ray, ray_t: Interval) -> (bool, HitRecord) {

	if did_hit, _ := aabb_hit(bvh_node.bbox, r, ray_t); !did_hit {
		return false, HitRecord{}
	}

	hit_left, rec := hittable_hit(bvh_node.left^, r, ray_t)
	hit_right, rec2 := hittable_hit(bvh_node.right^, r, Interval{ray_t.min, hit_left ? rec.t : ray_t.max})

	if hit_right {
		return true, rec2
	}

	if hit_left {
		return true, rec
	}

	return false, HitRecord{}
}

arena_new :: proc() -> mv.Arena {
	arena : mv.Arena
	arena_err := mv.arena_init_growing(&arena)
	ensure(arena_err == nil)
	return arena
}

TextureSolid :: struct {
	albedo: Color
}

TextureCheckered :: struct {
	inv_scale: f32,
	even: ^Texture,
	odd: ^Texture
}

TextureImage :: struct {
	width, height, nrChannels: i32,
	data : [^]byte,
}

TextureNoise :: struct {
	noise: Perlin,
	scale: f32
}

Texture :: union #no_nil {
	TextureSolid,
	TextureCheckered,
	TextureImage,
	TextureNoise,
}

texture_noise_new :: proc(scale: f32) -> (tex: Texture) {
	tex_i : TextureNoise
	tex_i.noise = perlin_new()
	tex_i.scale = scale

	tex = tex_i
	return
}

texture_get_value :: proc(tex: Texture, u, v: f32, p: point3) -> Color {


	switch tex_inner in tex {
	case TextureSolid:
		return tex_inner.albedo
	case TextureCheckered:

		xInteger := int(math.floor(tex_inner.inv_scale * p.x))
		yInteger := int(math.floor(tex_inner.inv_scale * p.y))
		zInteger := int(math.floor(tex_inner.inv_scale * p.z))

		isEven := (xInteger + yInteger + zInteger) % 2 == 0

		return isEven ? texture_get_value(tex_inner.even^, u, v, p) : texture_get_value(tex_inner.odd^, u, v, p)
	case TextureImage:
		if (tex_inner.height <= 0) do return Color{1,1,1}

		// Clamp input texture coordinates to [0,1] x [1,0]
		u_c := interval_clamp({0, 1}, u)
		v_c := 1 - interval_clamp({0, 1}, v)

		i := int(u_c * cast(f32)tex_inner.width)
		j := int(v_c * cast(f32)tex_inner.height)

		// Sampling Image
		pixel := texture_image_get_pixel_data(tex_inner, i, j)

		color_scale : f32 = 1.0 / 255.0
		return Color{color_scale*cast(f32)pixel[0], color_scale*cast(f32)pixel[1], color_scale*cast(f32)pixel[2]}
	case TextureNoise:
		// return Color{1, 1, 1} * 0.5 * (1 + perlin_do_noise(tex_inner.noise, tex_inner.scale * p))
		// return Color{1, 1, 1} * perlin_do_turbulence(tex_inner.noise, p, 7)
		return Color{.5,.5,.5} * (1 + linalg.sin(tex_inner.scale * p.z + 10 * perlin_do_turbulence(tex_inner.noise, p, 7)))
	case:
		panic("wut?")
	}
}

texture_image_new :: proc(image_path: string) -> Texture {
	tex_r := Texture(TextureImage{})
	tex_i := &tex_r.(TextureImage)

	image_path_cstr := strings.clone_to_cstring(image_path, context.temp_allocator)
	tex_i.data = stbi.load(image_path_cstr, &tex_i.width, &tex_i.height, &tex_i.nrChannels, 0)
	ensure(tex_i.data != nil)

	return tex_r
}

// Return the the 3  RGB bytes of the pixel at x,y. If there is no image
// data, returns magenta.
texture_image_get_pixel_data :: proc(tex: TextureImage, x, y: int) -> (res: [3]byte) {

	if (tex.data == nil) do return {255, 0, 255}

	x_i := math.clamp(x, 0, cast(int)tex.width)
	y_i := math.clamp(y, 0, cast(int)tex.height)

	bytes_per_pixel := cast(int)tex.nrChannels

	mem.copy(&res, &tex.data[y_i * (cast(int)tex.width * bytes_per_pixel) + x_i * bytes_per_pixel], 3)
	return
	// return bdata + y*bytes_per_scanline + x*bytes_per_pixel
}


PERLIN_POINT_COUNT :: 256
Perlin :: struct {
	randvec : [PERLIN_POINT_COUNT]v3,
	perm_x : [PERLIN_POINT_COUNT]int,
	perm_y : [PERLIN_POINT_COUNT]int,
	perm_z : [PERLIN_POINT_COUNT]int,
}

perlin_new :: proc() -> (res: Perlin) {
	for i in 0..<PERLIN_POINT_COUNT {
		res.randvec[i] = linalg.normalize(v3_random_range(-1, 1))
	}

	perlin_generate_perm(res.perm_x[:])
	perlin_generate_perm(res.perm_y[:])
	perlin_generate_perm(res.perm_z[:])

	return
}

perlin_generate_perm :: proc(perm: []int) {
	for &perm, i in perm {
		perm = i
	}

	perlin_permute(perm)
}

perlin_permute :: proc(perm: []int) {
	for i := len(perm) - 1; i > 0; i -= 1 {
		target := random_int(0, i)
		tmp := perm[i]
		perm[i] = perm[target]
		perm[target] = tmp
	}
}

perlin_do_noise :: proc(perlin: Perlin, p: point3) -> f32 {

	u := p.x - linalg.floor(p.x)
	v := p.y - linalg.floor(p.y)
	w := p.z - linalg.floor(p.z)

	i := int(linalg.floor(p.x))
	j := int(linalg.floor(p.y))
	k := int(linalg.floor(p.z))
	c : [2][2][2]v3

	for di in 0..<2 {
		for dj in 0..<2 {
			for dk in 0..<2 {
				c[di][dj][dk] = perlin.randvec [
				perlin.perm_x[(i+di) & 255] ~
				perlin.perm_y[(j+dj) & 255] ~
				perlin.perm_z[(k+dk) & 255]
				]
			}
		}
	}

	return perlin_interp(c, u, v, w)
}

perlin_do_turbulence :: proc(perlin: Perlin, p: point3, depth: int) -> f32 {
	accum : f32
	temp_p := p
	weight : f32 = 1.0

	for _ in 0..<depth {
		accum += weight * perlin_do_noise(perlin, temp_p)
		weight *= 0.5
		temp_p *= 2
	}

	return abs(accum)
}

perlin_interp :: proc(c : [2][2][2]v3, u, v, w: f32) -> f32 {

	uu := u*u*(3-2*u)
	vv := v*v*(3-2*v)
	ww := w*w*(3-2*w)
	accum : f32


	for i in 0..<2 {
		for j in 0..<2 {
			for k in 0..<2 {

				i_f := f32(i)
				j_f := f32(j)
				k_f := f32(k)

				weight_v := v3{u-i_f, v-j_f, w-k_f}
				accum += ((i_f*uu + (1-i_f) *(1-uu)) *
					(j_f*vv + (1-j_f)*(1-vv)) *
					(k_f*ww + (1-k_f)*(1-ww)) *
					linalg.dot(c[i][j][k], weight_v))
			}
		}
	}

	return accum
}

perlin_trilinear_lerp :: proc(c: [2][2][2]f32, u, v, w:f32) -> f32 {

	accum : f32

	for i in 0..<2 {
		for j in 0..<2 {
			for k in 0..<2 {

				i_f := f32(i)
				j_f := f32(j)
				k_f := f32(k)

				accum += (i_f*u + (1-i_f)*(1-u)) * (j_f*v + (1-j_f)*(1-v)) * (k_f*w + (1-k_f)*(1-w)) * c[i][j][k]
			}
		}
	}

	return accum
}

Quad :: struct {
	Q: point3,
	u, v: v3,
	w: v3,
	mat: ^Material,
	bbox: AABB,
	normal: v3,
	D: f32,
}

quad_new :: proc(Q: point3, u,v : v3, mat: ^Material) -> (res: Quad) {

	res = {
		Q = Q,
		u = u,
		v = v,
		mat = mat,
	}

	n := linalg.cross(res.u, res.v)
	res.normal = linalg.normalize(n)
	res.D = linalg.dot(res.normal, res.Q)
	res.w = n / linalg.dot(n, n)

	quad_set_bounding_box(&res)

	return
}

// Compute the bounding box of all four vertices.
quad_set_bounding_box :: proc(quad: ^Quad) {
	bbox_diagonal1 := aabb_new(quad.Q, quad.Q + quad.u + quad.v)
	bbox_diagonal2 := aabb_new(quad.Q + quad.u, quad.Q + quad.v)
	quad.bbox = aabb_union(bbox_diagonal1, bbox_diagonal2)
}

quad_hit :: proc(quad: Quad, r: Ray, ray_t: Interval) -> (hit: bool, rec: HitRecord) {


	denom := linalg.dot(quad.normal, r.direction)

	// No hit if the ray is parallel to the plane.
	if abs(denom) < 1e-8 do return false, rec

	// Return false if the hit point parameter t is outside the ray interval.
	t := (quad.D - linalg.dot(quad.normal, r.origin)) / denom
	if !interval_contains(ray_t, t) do return false, rec


	// Determine if the hit point lies within the planar shape using its plane coordinates.
	intersection := ray_at(r, t)

	planar_hitpt_vector := intersection - quad.Q
	alpha := linalg.dot(quad.w, linalg.cross(planar_hitpt_vector, quad.v))
	beta := linalg.dot(quad.w, linalg.cross(quad.u, planar_hitpt_vector))

	unit_interval := Interval{0, 1}

	// Given the hit point in plane coordinates, return false if it is outside the
	// primitive, otherwise set the hit record UV coordinates and return true.
	if !interval_contains(unit_interval, alpha) || !interval_contains(unit_interval, beta) do return false, rec

	// Ray hits the 2D shape; set the rest of the hit record and return true.
	rec.u = alpha
	rec.v = beta
	rec.t = t
	rec.p = intersection
	rec.mat = quad.mat

	hr_set_face_normal(&rec, r, quad.normal)

	return true, rec
}

Translate :: struct {
	object: ^Hittable,
	offset: v3,
	bbox: AABB,
}

translate_new :: proc(object: ^Hittable, offset: v3) -> (hittable: Hittable) {
	res := Translate {
		object = object,
		offset = offset
	}

	res.bbox = aabb_translate(hittable_get_bounding_box(object^), offset)
	return res
}

translate_hit :: proc(translate: Translate, r: Ray, ray_t: Interval) -> (bool, HitRecord) {

	// Move the ray backwards by the offset
	ray_offset := Ray{r.origin - translate.offset, r.direction, r.time}

	// Determine whether an intersection exists along the offset ray (and if so, where)
	did_hit, hr := hittable_hit(translate.object^, ray_offset, ray_t)

	if  !did_hit do return false, {}

	// Move the intersection point forwards by the offset
	hr.p += translate.offset

	return true, hr
}

Rotate_Y :: struct {
	object: ^Hittable,
	sin_theta, cos_theta: f32,
	bbox : AABB
}

rotate_new :: proc(object: ^Hittable, angle: f32) -> Hittable {
	radians := degrees_to_radians(angle)
	rot := Rotate_Y {
		object = object,
		sin_theta = linalg.sin(radians),
		cos_theta = linalg.cos(radians),
		bbox = hittable_get_bounding_box(object^)
	}

	min := point3{INFINITY, INFINITY, INFINITY}
	max := point3{-INFINITY, -INFINITY, -INFINITY}

	for i in 0..<2 {
		for j in 0..<2 {
			for k in 0..<2{

				i_f := cast(f32)i
				j_f := cast(f32)j
				k_f := cast(f32)k

				x := i_f*rot.bbox.x.max + (1-i_f)*rot.bbox.x.min
				y := j_f*rot.bbox.y.max + (1-j_f)*rot.bbox.y.min
				z := k_f*rot.bbox.z.max + (1-k_f)*rot.bbox.z.min

				newx :=  rot.cos_theta*x + rot.sin_theta*z
				newz := -rot.sin_theta*x + rot.cos_theta*z

				tester := v3{newx, y, newz}

				for c in 0..<3 {
					min[c] = linalg.min(min[c], tester[c])
					max[c] = linalg.max(max[c], tester[c])
				}
			}
		}
	}

	rot.bbox = aabb_new(min, max)

	return rot
}

rotate_hit :: proc(rotate: Rotate_Y, r: Ray, ray_t: Interval) -> (bool, HitRecord) {


	// Transform the ray from world space to object space.
	origin := point3{
		(rotate.cos_theta * r.origin.x) - (rotate.sin_theta * r.origin.z),
		r.origin.y,
		(rotate.sin_theta * r.origin.x) + (rotate.cos_theta * r.origin.z)
	}

	direction := v3{
		(rotate.cos_theta * r.direction.x) - (rotate.sin_theta * r.direction.z),
		r.direction.y,
		(rotate.sin_theta * r.direction.x) + (rotate.cos_theta * r.direction.z)
	}

	rotated_r := Ray{origin, direction, r.time}

	// Determine whether an intersection exists in object space (and if so, where).
	did_hit, rec := hittable_hit(rotate.object^, rotated_r, ray_t)

	if !did_hit do return false, {}

	// Transform the intersection from object space back to world space.
	rec.p = point3{
		(rotate.cos_theta * rec.p.x) + (rotate.sin_theta * rec.p.z),
		rec.p.y,
		(-rotate.sin_theta * rec.p.x) + (rotate.cos_theta * rec.p.z)
	}

	rec.normal = v3{
		(rotate.cos_theta * rec.normal.x) + (rotate.sin_theta * rec.normal.z),
		rec.normal.y,
		(-rotate.sin_theta * rec.normal.x) + (rotate.cos_theta * rec.normal.z)
	}

	return true, rec
}

HittableList :: struct {
	objects: [dynamic]Hittable,
	bbox: AABB
}

hittable_list_hit :: proc(hlist: HittableList, r: Ray, ray_t: Interval) -> (hit: bool, rec: HitRecord) {
	closest_so_far := ray_t.max

	for object in hlist.objects {
		did_hit, object_hr := hittable_hit(object, r, Interval{ray_t.min, closest_so_far})
		if did_hit {
			hit = true
			closest_so_far = object_hr.t
			rec = object_hr
		}
	}

	return
}

hittable_list_add :: proc(hlist: ^HittableList, object: Hittable) {
	append(&hlist.objects, object)
	hlist.bbox = aabb_union(hlist.bbox, hittable_get_bounding_box(object))
}

ConstantMedium :: struct {
	boundary: ^Hittable,
	neg_inv_density: f32,
	phase_function: ^Material
}

constant_medium_hit :: proc(cm: ConstantMedium, r: Ray, ray_t: Interval) -> (hit: bool, rec: HitRecord) {

	did_hit_1, rec1 := hittable_hit(cm.boundary^, r, interval_universe)
	if !did_hit_1 do return false, {}

	did_hit_2, rec2 := hittable_hit(cm.boundary^, r, Interval{rec1.t + 0.0001, INFINITY})
	if !did_hit_2 do return false, {}

	if rec1.t < ray_t.min do rec1.t = ray_t.min
	if rec2.t > ray_t.max do rec2.t = ray_t.max

	if rec1.t >= rec2.t do return false, {}

	if rec1.t < 0 do rec1.t = 0

	ray_length := linalg.length(r.direction)
	distance_inside_boundary := (rec2.t - rec1.t) * ray_length
	hit_distance := cm.neg_inv_density * linalg.ln(random_double())
	if hit_distance > distance_inside_boundary do return false, {}

	rec.t = rec1.t + hit_distance / ray_length
	rec.p = ray_at(r, rec.t)

	rec.normal = v3{1,0,0} // arbitrary
	rec.front_face = true // arbitrary
	rec.mat = cm.phase_function

	return true, rec
}

TextureOrColor :: union #no_nil {
	^Texture,
	Color
}

texture_or_color_sample :: proc(tex_or_color: TextureOrColor, u,v : f32, p: point3) -> Color {
	switch t_inner in tex_or_color {
	case ^Texture:
		return texture_get_value(t_inner^, u, v, p)
	case Color:
		return t_inner
	}
	panic("invalid union value")
}

constant_medium_new :: proc(boundary: ^Hittable, density: f32, tex_or_color: TextureOrColor) -> Hittable {
	return ConstantMedium  {
		boundary = boundary,
		neg_inv_density = -1 / density,
		phase_function = new_clone(Material(Mat_Isotropic{tex_or_color}))
	}
}
