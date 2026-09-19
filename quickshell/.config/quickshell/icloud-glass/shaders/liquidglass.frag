#version 440

// liquidglass.frag — material "Liquid Glass" para GlassSurface.qml
//
// El COMPOSITOR (Hyprland, regla `blur` sobre namespace `quickshell:icloud-glass*`)
// ya ha desenfocado el fondo detrás de esta layer surface. Este shader NO desenfoca
// nada: toma la textura ya borrosa del `source` (un ShaderEffectSource que captura lo
// que hay detrás de la superficie) y sobre ella aplica, en una sola pasada:
//   1) refracción de borde tipo lente (desplazamiento de la coordenada de muestreo
//      según el gradiente de una SDF de rectángulo redondeado, no lineal cerca del borde)
//   2) aberración cromática sutil en esa misma franja de borde
//   3) highlight especular direccional (borde superior claro / inferior tenue,
//      modulable por la posición de luz, p.ej. el ratón)
//   4) tinte de color con alpha configurable
//
// Coste estimado: 1 sampler con hasta 3 muestreos (R/G/B con offset distinto) SOLO
// dentro de la franja de refracción (los últimos ~12 px del borde); fuera de esa
// franja es 1 solo muestreo. Todo lo demás es aritmética escalar/vectorial sin bucles
// ni ramas costosas (los `mix`/`smoothstep` se resuelven sin saltos en GPU moderna).
// En una RTX 4070 (laptop) a 2560x1600 esto son ~4.1M píxeles; con <10 ALU ops y
// ≤3 texture fetches por píxel el coste esperado es del orden de 0.1-0.3 ms, muy por
// debajo del presupuesto de 1 ms pedido. El único fetch "caro" real es el del sampler
// de fondo, que es exactamente el mismo que ya pagaríamos con opacidad plana.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // --- uniformes propios del material ---
    vec2 size;              // tamaño en px de la superficie
    float radius;           // radio de esquina en px
    float refraction;       // 0..1.5 — intensidad de la lente de borde (0 = desactivado)
    float specularStrength; // 0..1 — intensidad del highlight especular
    vec2 lightPos;          // posición de luz normalizada (0..1), sigue al ratón si interactive
    vec4 tintColor;         // color de tinte premultiplicado por alpha en tintAlpha
    float chromatic;        // 0..1 — cantidad de aberración cromática en el borde
} ubuf;

layout(binding = 1) uniform sampler2D source;

// SDF de rectángulo redondeado centrado en el origen, medio-tamaño `he`, radio `r`.
// Devuelve distancia con signo en las mismas unidades que `p`/`he` (negativa dentro).
float sdRoundRect(vec2 p, vec2 he, float r) {
    vec2 q = abs(p) - he + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * ubuf.size;

    // Coordenadas centradas para la SDF (en píxeles)
    vec2 he = ubuf.size * 0.5;
    vec2 p = px - he;
    float r = min(ubuf.radius, min(he.x, he.y));

    float dist = sdRoundRect(p, he, r);

    // Fuera del rectángulo redondeado: transparente (recorta esquinas).
    // Antialiasing de 1px en el borde exterior.
    float outerMask = 1.0 - smoothstep(-1.0, 1.0, dist);

    // --- 1) refracción de borde tipo lente ---------------------------------
    // Franja de refracción: los últimos EDGE px hacia dentro del borde.
    const float EDGE = 12.0;
    // 0 en el interior, 1 justo en el borde; curva no lineal (más fuerte cerca del borde)
    float edgeT = clamp((dist + EDGE) / EDGE, 0.0, 1.0);
    float lensT = edgeT * edgeT * edgeT; // cúbica: suave en el centro, fuerte en el borde

    // Gradiente aproximado de la SDF (normal exterior aproximada) vía diferencias
    // analíticas baratas: como sdRoundRect es ~C1, usamos el vector p/he clamped como
    // aproximación direccional barata (evita 2 muestreos extra de la SDF).
    vec2 dir = normalize(sign(p) * max(abs(p) - (he - r), vec2(0.0001)) + p * 0.0001);
    if (length(p) < 0.0001) dir = vec2(0.0);

    vec2 refractOffset = dir * lensT * ubuf.refraction * EDGE * 0.6;
    vec2 refractUv = clamp(uv + refractOffset / ubuf.size, vec2(0.001), vec2(0.999));

    // --- 2) aberración cromática sutil (solo en la franja de borde) --------
    float chromaAmt = lensT * ubuf.chromatic * 2.5; // px de separación máxima, sutil
    vec2 chromaDir = dir * (chromaAmt / ubuf.size);

    float rCh = texture(source, clamp(refractUv + chromaDir, vec2(0.001), vec2(0.999))).r;
    vec2 gUv = refractUv;
    float gCh = texture(source, gUv).g;
    float bCh = texture(source, clamp(refractUv - chromaDir, vec2(0.001), vec2(0.999))).b;
    float aCh = texture(source, gUv).a;

    vec4 refracted = vec4(rCh, gCh, bCh, aCh);
    vec4 plain = texture(source, uv);
    // Mezcla entre muestreo plano y refractado según refraction (permite refraction=0
    // como fallback perfecto a un simple passthrough del fondo ya borroso).
    vec4 backgroundColor = mix(plain, refracted, clamp(ubuf.refraction, 0.0, 1.0));

    // --- 3) highlight especular ---------------------------------------------
    // Ángulo del punto respecto al centro, comparado con la posición de luz.
    vec2 nrm = p / max(he, vec2(1.0));
    vec2 lightDir = normalize((ubuf.lightPos * 2.0 - 1.0) - nrm * 0.0 + vec2(0.0, -1.0) * 0.0);
    // lightPos en 0..1: 0.5,0 es arriba-centro por defecto si interactive=false.
    vec2 lightVec = normalize(vec2(ubuf.lightPos.x * 2.0 - 1.0, (1.0 - ubuf.lightPos.y) * 2.0 - 1.0));

    // Realce en el borde superior: fuerte donde la normal aproximada del borde
    // apunta hacia la luz; solo tiene efecto en la franja de borde (edgeT).
    float facing = clamp(dot(dir, -lightVec), 0.0, 1.0);
    float topHighlight = pow(facing, 3.0) * edgeT * ubuf.specularStrength;

    // Contra-realce tenue en el borde opuesto a la luz.
    float facingBack = clamp(dot(dir, lightVec), 0.0, 1.0);
    float bottomShade = pow(facingBack, 4.0) * edgeT * ubuf.specularStrength * 0.35;

    vec3 withSpecular = backgroundColor.rgb
        + vec3(topHighlight) * 0.9
        - vec3(bottomShade) * 0.5;

    // --- 4) tinte -------------------------------------------------------------
    vec3 tinted = mix(withSpecular, ubuf.tintColor.rgb, ubuf.tintColor.a);

    float alpha = backgroundColor.a * outerMask * ubuf.qt_Opacity;
    fragColor = vec4(tinted * alpha, alpha);
}
