//Tasks:
// Config.BitSet is not parsed
// Config.HasKey is not implemented, config needs all sections without defaults

package tomato

import "core:fmt"
import rl "vendor:raylib"
import "core:strings"
import "core:time"
import "core:os"
import "base:runtime"
import ini "core:encoding/ini"
import "core:strconv"

CurrentScreen :: enum {
	INIT,
	WAIT_FOR_START,
	IN_PROGRESS,
	IN_REST
}

BUFFER_LENGTH :: 255
SAVEDATA_FILE :: "database.txt"
CONFIG_FILE :: "config.ini"
REST_TIME_IN_SECONDS :: 5 * 60
TASK_TIME_IN_SECONDS :: 25 * 60


ToggleSettings :: enum {
	SOUND_ENABLED,
	WINDOW_ALWAYS_ON_TOP,
	WINDOW_BRING_TO_FRONT_ON_STATE_CHANGE,

}

Config :: struct {
	options : bit_set[ToggleSettings],
	path_savedata_file : string,
	path_sound_task_complete : string,
	path_sound_rest_complete : string,

	rest_time_in_seconds : i32,
	task_time_in_seconds : i32,
	long_rest_time_in_seconds : i32,
	long_rest_every_n_tasks: i32,

	window_resolution: [2]i32,


	// style

	font_size_completed_tasks: i32,
	font_size_rest_timer: i32,
	font_size_task_timer: i32,
	font_size_rest_header: i32,
	font_size_task_header: i32,
	font_size_init_header: i32,

	color_completed_tasks_text: rl.Color,
	color_init_background: rl.Color,
	color_init_text: rl.Color,
	color_rest_background: rl.Color,
	color_rest_text: rl.Color,
	color_task_background: rl.Color,
	color_task_text: rl.Color,
}

State :: struct {
	completed_tasks: [dynamic]cstring,
	current_task: string,
	time_display: cstring,
	time_buffer: []u8,
	input_buffer: strings.Builder,
	screen : CurrentScreen,
	rest_time : f32,
	task_time: f32,
	active_task_time : f32,
	active_rest_time : f32
}


config_default :: proc(config: ^Config) {
	config.options = {}
	config.path_savedata_file = SAVEDATA_FILE
	config.path_sound_task_complete = ""
	config.path_sound_rest_complete = ""

	config.rest_time_in_seconds = REST_TIME_IN_SECONDS
	config.task_time_in_seconds = TASK_TIME_IN_SECONDS
	config.long_rest_time_in_seconds = 0
	config.long_rest_every_n_tasks = -1

	config.window_resolution = {1280, 720}
	// style
	config.font_size_completed_tasks = 24
	config.font_size_rest_timer = 40
	config.font_size_task_timer = 40
	config.font_size_rest_header = 40
	config.font_size_task_header = 40
	config.font_size_init_header = 40
	config.color_completed_tasks_text = rl.Color{128, 128, 128, 255}
	config.color_init_background = rl.Color{255,255,255, 255}
	config.color_init_text = rl.Color{0,0,0, 255}
	config.color_rest_background = rl.Color{64, 255, 32, 255}
	config.color_rest_text = rl.Color{0,0,0, 255}
	config.color_task_background = rl.Color{64, 32, 255, 255}
	config.color_task_text = rl.Color{0,0,0, 255}
}


Config_Error :: enum {
	None = 0,
	File_Not_Found,
	Cannot_Open_File,
}

Error :: union #shared_nil{
	runtime.Allocator_Error,
	Config_Error
}


wait_for_input_to_complete :: proc(state : ^State) {
	key := rl.GetCharPressed()
	for key > 0 {
		if key >= 32 && key <= 125 && strings.builder_space(state.input_buffer) > 0 {
			strings.write_byte(&state.input_buffer, u8(key))
		}
		key = rl.GetCharPressed()
	}

	if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
		strings.pop_byte(&state.input_buffer)
	}

	if rl.IsKeyPressed(rl.KeyboardKey.ENTER) && strings.builder_len(state.input_buffer) > 0 {
		state.current_task = strings.clone(strings.to_string(state.input_buffer))
		strings.builder_reset(&state.input_buffer)
		state.active_task_time = state.task_time
		state.screen = .IN_PROGRESS
	}
}

write_duration :: proc(seconds: f32, buffer: []u8) -> cstring {
	duration := time.Duration(int(seconds))* time.Second
	duration_string := time.duration_to_string_hms(duration, buffer)
	return strings.unsafe_string_to_cstring(duration_string)
}

run_progress :: proc(config: ^Config, state : ^State, deltaTime: f32){
	state.active_task_time -= deltaTime
	state.time_display = write_duration(state.active_task_time, state.time_buffer)
	if state.active_task_time <= 0 {
		state.screen = .IN_REST
		state.active_rest_time = state.rest_time
		append(&state.completed_tasks, strings.clone_to_cstring(state.current_task))
		write_tasks(config, state)
	}
}

run_rest :: proc(state: ^State, deltaTime: f32){
	state.active_rest_time -= deltaTime
	state.time_display = write_duration(state.active_rest_time, state.time_buffer)
	if state.active_rest_time <= 0 {
		state.screen = .WAIT_FOR_START
	}
}



config_to_map :: proc(config: ^Config) -> ini.Map {
	ini_map : ini.Map = make(ini.Map, allocator = context.temp_allocator)
	ini_map_paths := make(map[string]string, allocator = context.temp_allocator)
	ini_map_paths["save_file"] = config.path_savedata_file
	// ini_map_paths["sound_rest_complete"] = config.path_sound_rest_complete
	// ini_map_paths["sound_task_complete"] = config.path_sound_task_complete
	ini_map["Paths"] = ini_map_paths
	ini_map_settings := make(map[string]string, allocator = context.temp_allocator)
	ini_map_settings["rest_time_in_seconds"] = fmt.aprint(config.rest_time_in_seconds)
	ini_map_settings["task_time_in_seconds"] = fmt.aprint(config.task_time_in_seconds)
	// ini_map_settings["long_rest_time_in_seconds"] = fmt.aprint(config.long_rest_time_in_seconds)
	// ini_map_settings["long_rest_every_n_tasks"] = fmt.aprint(config.long_rest_every_n_tasks)
	ini_map["Settings"] = ini_map_settings


	ini_map_style := make(map[string]string, allocator = context.temp_allocator)
	ini_map_style["window_resolution"] = fmt.aprint(config.window_resolution)
	ini_map_style["font_size_completed_tasks"] = fmt.aprint(config.font_size_completed_tasks)
	ini_map_style["font_size_rest_timer"] = fmt.aprint(config.font_size_rest_timer)
	ini_map_style["font_size_task_timer"] = fmt.aprint(config.font_size_task_timer)
	ini_map_style["font_size_rest_header"] = fmt.aprint(config.font_size_rest_header)
	ini_map_style["font_size_task_header"] = fmt.aprint(config.font_size_task_header)
	ini_map_style["font_size_init_header"] = fmt.aprint(config.font_size_init_header)
	ini_map_style["color_completed_tasks_text"] = fmt.aprint(config.color_completed_tasks_text)
	ini_map_style["color_init_background"] = fmt.aprint(config.color_init_background)
	ini_map_style["color_init_text"] = fmt.aprint(config.color_init_text)
	ini_map_style["color_rest_background"] = fmt.aprint(config.color_rest_background)
	ini_map_style["color_rest_text"] = fmt.aprint(config.color_rest_text)
	ini_map_style["color_task_background"] = fmt.aprint(config.color_task_background)
	ini_map_style["color_task_text"] = fmt.aprint(config.color_task_text)
	ini_map["Style"] = ini_map_style
	return ini_map
}


config_read :: proc(config: ^Config) -> Error {
	ini_map, err, ok := ini.load_map_from_path(CONFIG_FILE, context.allocator)
	if !ok {
		if err == nil {
			return Config_Error.File_Not_Found
		}
		return err
	}
	config.path_savedata_file = config_parse_path(ini_map["Paths"]["save_file"])
	config.path_sound_rest_complete = config_parse_path(ini_map["Paths"]["sound_rest_complete"])
	config.path_sound_task_complete = config_parse_path(ini_map["Paths"]["sound_task_complete"])
	config.rest_time_in_seconds = config_parse_i32(ini_map["Settings"]["rest_time_in_seconds"])
	config.task_time_in_seconds = config_parse_i32(ini_map["Settings"]["task_time_in_seconds"])
	config.long_rest_time_in_seconds = config_parse_i32(ini_map["Settings"]["long_rest_time_in_seconds"])
	config.long_rest_every_n_tasks = config_parse_i32(ini_map["Settings"]["long_rest_every_n_tasks"])
	config.window_resolution = config_parse_number_array(ini_map["Style"]["window_resolution"], 2, i32)
	config.font_size_completed_tasks = config_parse_i32(ini_map["Style"]["font_size_completed_tasks"])
	config.font_size_rest_timer = config_parse_i32(ini_map["Style"]["font_size_rest_timer"])
	config.font_size_task_timer = config_parse_i32(ini_map["Style"]["font_size_task_timer"])
	config.font_size_rest_header = config_parse_i32(ini_map["Style"]["font_size_rest_header"])
	config.font_size_task_header = config_parse_i32(ini_map["Style"]["font_size_task_header"])
	config.font_size_init_header = config_parse_i32(ini_map["Style"]["font_size_init_header"])
	config.color_completed_tasks_text = config_parse_color(ini_map["Style"]["color_completed_tasks_text"])
	config.color_init_background = config_parse_color(ini_map["Style"]["color_init_background"])
	config.color_init_text = config_parse_color(ini_map["Style"]["color_init_text"])
	config.color_rest_background = config_parse_color(ini_map["Style"]["color_rest_background"])
	config.color_rest_text = config_parse_color(ini_map["Style"]["color_rest_text"])
	config.color_task_background = config_parse_color(ini_map["Style"]["color_task_background"])
	config.color_task_text = config_parse_color(ini_map["Style"]["color_task_text"])
	return nil
}

config_parse_path :: proc(value : string) -> string {
	return value
}

config_parse_i32 :: proc(value : string) -> i32 {
	v := strconv.parse_int(value) or_else 0
	return i32(v)
}

config_parse_color :: proc(value : string) -> rl.Color {
	parsed_value := config_parse_number_array(value, 4, u8)
	fmt.println(parsed_value)
	return rl.Color(parsed_value)
}

config_parse_number_array :: proc(value : string, $N: $I, $T: typeid) -> (res:[N]T) {
	parse_value := strings.trim(value, "[] ")
	split := strings.split_n(parse_value, ",", N, context.temp_allocator)
	assert(len(split) == N)
	for i in 0..<N {
		res[i] = T(strconv.parse_int(strings.trim(split[i], " ")) or_else 0)
	}
	return res
}

config_save :: proc(config : ^Config)
{
	ini_map := config_to_map(config)
	//@bug: ODIN encoding/ini writes sections without linebreaks, so - need to implement my own or inject linebreaks into the resulting string (Artem)
	map_content := ini.save_map_to_string(ini_map, context.temp_allocator)
	os.write_entire_file(CONFIG_FILE, transmute([]u8)map_content)
	free_all(context.temp_allocator)
}

main :: proc() {

	config : Config
	config_default(&config)

	if config_read(&config) != nil {
		config_save(&config)
	}

	rl.InitWindow(config.window_resolution.x, config.window_resolution.y, "Tomato Soup")
	defer rl.CloseWindow()
	
	buffer := strings.builder_make_len_cap(0, BUFFER_LENGTH)
	defer strings.builder_destroy(&buffer)

	time_buffer := new([time.MIN_HMS_LEN]u8)
	defer free(time_buffer)

	tasks := make([dynamic]cstring)
	defer free(&tasks)

	content, loaded := os.read_entire_file_from_filename(config.path_savedata_file)
	if loaded {
		tasks_list := string(content)
		for s in strings.split_lines_iterator(&tasks_list) {
			append(&tasks, strings.clone_to_cstring(s))
		}
	}
	state := State{
		completed_tasks = tasks,
		current_task = "",
		input_buffer = buffer,
		screen = .WAIT_FOR_START,
		rest_time = f32(config.rest_time_in_seconds),
		task_time = f32(config.task_time_in_seconds),
		active_rest_time = 0,
		active_task_time = 0,
		time_buffer = time_buffer[:]
	}

	rl.SetTargetFPS(60)
	for rl.WindowShouldClose() == false {
		deltaTime := rl.GetFrameTime()
		switch state.screen {
			case .INIT: state.screen = .WAIT_FOR_START
			case .WAIT_FOR_START: wait_for_input_to_complete(&state)
			case .IN_PROGRESS: run_progress(&config, &state, deltaTime)
			case .IN_REST: run_rest(&state, deltaTime)
		}

		rl.BeginDrawing()
		switch state.screen {
			case .INIT: {
				rl.ClearBackground(rl.BLACK)
			}
			case .WAIT_FOR_START: 
			{
				rl.ClearBackground(config.color_init_background)
				rl.DrawText("PLEASE INPUT TASK:", 0, 100, config.font_size_init_header, config.color_init_text)
				rl.DrawText(strings.to_cstring(&state.input_buffer), 0, 300, config.font_size_init_header, config.color_init_text)
			}
			case .IN_PROGRESS: {
				rl.ClearBackground(config.color_task_background)
				rl.DrawText("WORKING", 0, 100, config.font_size_task_header, config.color_task_text)
				rl.DrawText(strings.unsafe_string_to_cstring(state.current_task), 0, 200, config.font_size_task_header, config.color_task_text)
				rl.DrawText(state.time_display, 0, 300, config.font_size_task_timer, config.color_task_text)
			}
			case .IN_REST: {
				rl.ClearBackground(config.color_rest_background)
				rl.DrawText("RESTING", 0, 100, config.font_size_rest_header, config.color_rest_text)
				rl.DrawText(state.time_display, 0, 300, config.font_size_rest_timer, config.color_rest_text)
			}
		}

		len := len(state.completed_tasks)
		for s, i in state.completed_tasks {
			rl.DrawText(s, 900, i32(25 * (len - i)), config.font_size_completed_tasks, config.color_completed_tasks_text)
		}

		rl.EndDrawing()
	}
}

write_tasks :: proc(config: ^Config, state: ^State) {
	fd, ok := os.open(config.path_savedata_file, os.O_CREATE, 0)
	if ok == 0 {
		for s in state.completed_tasks {
			os.write_string(fd, string(s))
			os.write_byte(fd, '\n')
		}	
		os.close(fd)
	}
}
