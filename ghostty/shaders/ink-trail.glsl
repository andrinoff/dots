// Ink trail: when the cursor jumps, it drags a short tapered stroke of ink
// from where it was, which dries up in a fraction of a second.

const float DURATION = 0.16;
const float MIN_JUMP_CELLS = 1.5;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 base = texture(iChannel0, fragCoord / iResolution.xy);
    fragColor = base;
    if (iFocus == 0) return;

    float t = iTime - iTimeCursorChange;
    if (t < 0.0 || t > DURATION) return;

    vec2 head = iCurrentCursor.xy + vec2(iCurrentCursor.z, -iCurrentCursor.w) * 0.5;
    vec2 from = iPreviousCursor.xy + vec2(iPreviousCursor.z, -iPreviousCursor.w) * 0.5;
    if (distance(head, from) < iCurrentCursor.z * MIN_JUMP_CELLS) return;

    float progress = t / DURATION;
    vec2 tail = mix(from, head, smoothstep(0.0, 1.0, progress));

    vec2 pa = fragCoord - tail;
    vec2 ba = head - tail;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    float radius = mix(0.1, 0.5, h) * min(iCurrentCursor.z, iCurrentCursor.w);
    float d = length(pa - ba * h) - radius;

    float fade = (1.0 - progress) * (1.0 - progress);
    float ink = (1.0 - smoothstep(-1.0, 1.0, d)) * fade * 0.8;
    fragColor = mix(base, vec4(iCurrentCursorColor.rgb, 1.0), ink);
}
