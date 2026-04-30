
precision highp float;

// From vertex shader
in vec2 vUv;

// Uniforms
uniform vec3 u_clearColor;

uniform float u_hitThresh;
uniform float u_maxDist;
uniform int u_maxSteps;

uniform vec3 u_camPos;
uniform mat4 u_camToWorldMat;
uniform mat4 u_camInvProjMat;

uniform vec3 u_lightDir;
uniform vec3 u_lightColor;

uniform float u_diffIntensity;
uniform float u_specIntensity;
uniform float u_ambientIntensity;
uniform float u_shininess;

uniform float u_time;


// ------ Surface struct ------
// Carries distance + color through the scene. Add more fields here as needed.

struct Surface {
    float dist;
    vec3  color;
};


// ------ Signed Distance Functions ------

float sdSphere( vec3 pos, float r ) {
    return length(pos) - r;
}

float sdBox( vec3 pos, vec3 b ) {
    vec3 q = abs(pos) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdTorus( vec3 pos, vec2 t ) {
    vec2 q = vec2(length(pos.xz) - t.x, pos.y);
    return length(q) - t.y;
}

float sdPyramid( vec3 pos, float height ) {
    float m2 = height*height + 0.25;

    pos.xz = abs(pos.xz);
    pos.xz = (pos.z > pos.x) ? pos.zx : pos.xz;
    pos.xz -= 0.5;

    vec3 q = vec3( pos.z, height*pos.y - 0.5*pos.x, height*pos.x + 0.5*pos.y );
    float s  = max(-q.x, 0.0);
    float t  = clamp((q.y - 0.5*pos.z) / (m2 + 0.25), 0.0, 1.0);
    float a  = m2*(q.x + s)*(q.x + s) + q.y*q.y;
    float b  = m2*(q.x + 0.5*t)*(q.x + 0.5*t) + (q.y - m2*t)*(q.y - m2*t);
    float d2 = min(q.y, -q.x*m2 - q.y*0.5) > 0.0 ? 0.0 : min(a, b);

    return sqrt((d2 + q.z*q.z) / m2) * sign(max(q.z, -pos.y));
}

float sdLink( vec3 pos, float le, float r1, float r2 ) {
    vec3 q = vec3(pos.x, max(abs(pos.y) - le, 0.0), pos.z);
    return length(vec2(length(q.xy) - r1, q.z)) - r2;
}

float sdPlane( vec3 p, vec4 n ) {
  // n must be normalized
  return dot(p,n.xyz) + n.w;
}  


// ------ Operators (float) ------
// For composing distances only — e.g. rounding: sdBox(...) - 0.25

float bsUnion( float d1, float d2 )              { return min(d1, d2); }
float bsSub  ( float d1, float d2 )              { return max(-d1, d2); }
float bsInt  ( float d1, float d2 )              { return max(d1, d2); }

float smUnion( float d1, float d2, float k ) {
    float h = clamp(0.5 + 0.5*(d2-d1)/k, 0.0, 1.0);
    return mix(d2, d1, h) - k*h*(1.0-h);
}
float smSub  ( float d1, float d2, float k ) {
    float h = clamp(0.5 - 0.5*(d2+d1)/k, 0.0, 1.0);
    return mix(d2, -d1, h) + k*h*(1.0-h);
}
float smInt  ( float d1, float d2, float k ) {
    float h = clamp(0.5 - 0.5*(d2-d1)/k, 0.0, 1.0);
    return mix(d2, d1, h) + k*h*(1.0-h);
}


// ------ Operators (Surface) ------
// Same operators but carry color through. Colors blend on smooth joins.

Surface bsUnion( Surface a, Surface b ) {
    if (a.dist < b.dist) {
        return a;
    } else {
        return b;
    }
}

Surface bsSub( Surface a, Surface b ) {
    if (-a.dist > b.dist) {
        return Surface(-a.dist, a.color);
    } else {
        return b;
    }
}

Surface smUnion( Surface a, Surface b, float k ) {
    float h = clamp(0.5 + 0.5*(b.dist - a.dist)/k, 0.0, 1.0);
    return Surface(
        mix(b.dist,  a.dist,  h) - k*h*(1.0-h),
        mix(b.color, a.color, h)
    );
}



// ------ Rotation Helpers ------

// radians
mat2 rot2D( float angle ) {
    float s = sin(angle), c = cos(angle);
    return mat2(c, -s, s, c);
}

// degrees
mat2 degrot2D( float angle ) {
    return rot2D(radians(angle));
}


// ***** ***** ***** Scene ***** ***** *****

Surface map( vec3 pos ) {
    vec3 sphereAPos = vec3(
        -cos(u_time *0.7) - 0.3 * cos(u_time * 2.3),
        -sin(u_time * 1.1) - 0.2 * sin(u_time * 3.1),
        0.0
    );
    vec3 apos = pos;
    apos -= sphereAPos;
    Surface sphereA  = Surface(sdSphere(apos, 0.5) , vec3(0.2, 0.3, 1.0));

    vec3 sphereBPos = vec3(
        cos(u_time * 1.1) + 0.3 * cos(u_time * 2.7),
        sin(u_time * 1.0) + 0.2 * sin(u_time * 0.8),
        0.0
    );
    vec3 bpos = pos;
    bpos -= sphereBPos;
    Surface sphereB = Surface(sdSphere(bpos, 0.4) , vec3(0.0, 1.0, 1.0));

    vec3 cpos = fract(pos) - 0.5;
    float constraint = sdBox(pos, vec3(10.0));

    Surface box = Surface(bsInt(sdBox(cpos, vec3(0.1)), constraint), vec3(0.0, 0.0, 0.0));


    Surface final1 = smUnion(box, sphereA, 0.5);
    Surface final2 = smUnion(final1, sphereB, 0.5);

    return final2;
}


// ***** ***** ***** Lighting & Marching ***** ***** *****

vec3 calcNormal( vec3 pos ) {
    float e = 0.0001;
    return normalize(vec3(
        map(pos + vec3(e, 0, 0)).dist - map(pos - vec3(e, 0, 0)).dist,
        map(pos + vec3(0, e, 0)).dist - map(pos - vec3(0, e, 0)).dist,
        map(pos + vec3(0, 0, e)).dist - map(pos - vec3(0, 0, e)).dist
    ));
}

float rayMarch( vec3 ray_origin, vec3 ray_dir ) {
    float t = 0.0;
    for (int i = 0; i < u_maxSteps; ++i) {
        vec3 pos = ray_origin + ray_dir * t;
        float d  = map(pos).dist;
        if (d < u_hitThresh || t > u_maxDist) break;
        t += d;
    }
    return t;
}

void main() {
    vec2 uv         = vUv.xy;
    vec3 ray_origin = u_camPos;
    vec3 ray_dir    = (u_camInvProjMat * vec4(uv * 2.0 - 1.0, 0.0, 1.0)).xyz;
    ray_dir         = normalize((u_camToWorldMat * vec4(ray_dir, 0.0)).xyz);

    float t = rayMarch(ray_origin, ray_dir);

    if (t >= u_maxDist) {
        gl_FragColor = vec4(u_clearColor, 1.0);
    } else {
        vec3 hitPos = ray_origin + ray_dir * t;
        Surface hit = map(hitPos);
        gl_FragColor = vec4(hit.color, 1.0);
    }
}
