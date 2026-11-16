shader_type canvas_item;
uniform sampler2D stexture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 res = vec2(320.0, 180.0);
uniform float max_pixelation = 4.0;
uniform float rotation_amount = 0.0;
uniform float color_lvl = 16.0;
uniform float dither_strength = 0.75;


// dithering matrix
float bayer4(vec2 position){
    int x = int(mod(position.x, 4.0));
    int y = int(mod(position.y, 4.0));
    if (y == 0){
        if (x == 0) return 0.0;
        if (x == 1) return 8.0;
        if (x == 2) return 2.0;
        return 10.0;
    } if (y == 1) {
        if (x == 0) return 12.0;
        if (x == 1) return 4.0;
        if (x == 2) return 14.0;
        return 6.0;
    } if (y == 2) {
        if (x == 0) return 3.0;
        if (x == 1) return 11.0;
        if (x == 2) return 1.0;
        return 9.0;
    } if (x == 0) return 15.0;
    if (x == 1) return 7.0;
    if (x == 2) return 13.0;
    return 5.0;
}

void fragment() {
    //increase pixelation on if camera shakes by rotation
    float pixelation_multiplier = mix(1.0, max_pixelation, rotation_amount);
    vec2 current_resolution = res / pixelation_multiplier;
    vec2 pos = floor(SCREEN_UV * current_resolution);
    vec2 uv = (pos + 0.5) / current_resolution; //sample center
    vec3 color = textureLod(stexture, uv, 0.0).rgb;
    float threshold = bayer4(pos);
    threshold = ((threshold + 0.5) / 16.0) - 0.5;
    threshold *= dither_strength;
    float levels = color_lvl - 1.0;
    color = floor(color * levels + threshold) / levels;
    COLOR = vec4(color, 1.0);
}