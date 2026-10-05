// YHDM Light Sharpen (CAS-style adaptive sharpening)
// Lightweight mobile-friendly: 4-neighbor unsharp with contrast-adaptive amount.
//!HOOK MAIN
//!BIND HOOKED

const float amount = 0.55;
const float sharp_clamp = 0.35;

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt  = HOOKED_pt;

    vec3 c     = HOOKED_tex(pos).rgb;
    vec3 up    = HOOKED_tex(pos + vec2(0.0,   pt.y)).rgb;
    vec3 down  = HOOKED_tex(pos + vec2(0.0,  -pt.y)).rgb;
    vec3 left  = HOOKED_tex(pos + vec2(-pt.x, 0.0)).rgb;
    vec3 right = HOOKED_tex(pos + vec2( pt.x, 0.0)).rgb;

    // 局部对比度: 平坦区域弱化锐化, 避免噪点放大; 边缘区域限制过冲
    float lmax = max(max(luma(up), luma(down)), max(luma(left), luma(right)));
    float lmin = min(min(luma(up), luma(down)), min(luma(left), luma(right)));
    float range = lmax - lmin;
    float adapt = clamp(1.0 - range * 2.5, 0.1, 1.0);

    // 拉普拉斯锐化
    vec3 sharp = 5.0 * c - (up + down + left + right);
    vec3 delta = (sharp - c) * amount * adapt;

    // 限制过冲
    delta = clamp(delta, -sharp_clamp, sharp_clamp);

    return vec4(c + delta, 1.0);
}
