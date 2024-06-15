// Sometime the leftmost screen doesn't have id 0
// not sure yet how to detect this automatically
var leftMostScreen = 1

// Some setup used by both reading and writing
var dir = mp.utils.split_path(mp.get_script_file())[0]
var rect_path = mp.utils.join_path(dir, "last_window_rect.txt")

// Read last window rect if present
try {
    var rect = mp.utils.read_file(rect_path).trim().split(' ')

    var x = rect[0]
    var y = rect[1]
    var width = rect[2]
    var height = rect[3]
    var window_ratio = width / height

    // var video_width = mp.get_property("dwidth")
    // var video_height = mp.get_property("height")
    // var video_ratio = video_width / video_height
    // print("Video ratio: " + video_width)

    // if (video_ratio != window_ratio) {
    //     var new_width = Math.floor(height * video_ratio)
    //     width = new_width
    // }

    mp.set_property("screen", leftMostScreen)
    var geometry = width + "x" + height + "+" + x + "+" + y
    dump("Set geometry: " + geometry)
    mp.set_property("geometry", geometry)
}
catch (e) {
    dump(e)
}

// Save the rect at shutdown
function save_rect() {
    var ps1_script = mp.utils.join_path(dir, "Get-Client-Rect.ps1")

    var output_obj = mp.utils.subprocess({ args: ["pwsh", "-File", ps1_script, String(mp.utils.getpid())], cancellable: false })

    // Debugging
    var keys = Object.keys(output_obj)
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i]
        var value = output_obj[key]
        print(key + ": " + value)
    }
    

    var output = output_obj.stdout
    mp.utils.write_file("file://" + rect_path, output)

    // show notification
    mp.commandv("show-text", "Window position saved", 1000)
}

// function change_ratio_follow_video() {
//     var video_ratio = mp.get_property("video-params/aspect")
//     var window_ratio = mp.get_property("osd-dimensions/aspect")
//     print(video_ratio)
//     print(window_ratio)

//     if (video_ratio != window_ratio) {
//         var height = mp.get_property("osd-dimensions/h")
//         var new_width = Math.floor(height * video_ratio)

//         var rect = mp.utils.read_file(rect_path).trim().split(' ')

//         var x = rect[0]
//         var y = rect[1]

//         print("New width: " + new_width)
//         print("height: " + height)

//         var geometry = new_width + "x" + height
//         mp.set_property("geometry", geometry)
//     }
// }


// print pid
// print("PID: " + mp.utils.getpid())

// mp.register_event("shutdown", save_rect)
mp.add_key_binding("Ctrl+p", "save_rect", save_rect)
// mp.add_key_binding("Ctrl+r", "change_ratio_follow_video", change_ratio_follow_video)