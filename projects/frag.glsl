
precision mediump float;

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



//Signed Distance Functions  
float sdSphere( vec3 pos, float r) {
    return length(pos) -r;
}

float sdBox( vec3 pos, vec3 b ) {
    vec3 q = abs(pos) - b;
    return(length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0));
}

float sdTorus( vec3 pos, vec2 t ) {
    vec2 q = vec2(length(pos.xz)-t.x,pos.y);
    return length(q)-t.y;
}

float sdLink( vec3 pos, float le, float r1, float r2 ) {
    vec3 q = vec3( pos.x, max(abs(pos.y)-le,0.0), pos.z );
    return length(vec2(length(q.xy)-r1,q.z)) - r2;
}



//------  Joining Operators  ------\\

//basic operators -- 'bs' means basic

float bsUnion( float d1, float d2 ) {
    return min(d1, d2);
}

float bsSub( float d1, float d2 ) {
    return max(-d1, d2);
}

float bsInt( float d1, float d2 ) {
    return max(d1, d2);
}

//smooth operator

float smUnion( float d1, float d2, float k ) {
    float h = clamp ( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix(d2, d1, h ) - k*h*(1.0-h);
}

float smSub( float d1, float d2, float k ) {
    float h = clamp (0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix(d2, -d1, h ) + k*h*(1.0-h);
}

float smInt( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h);
}

//------ JOINING WITH COLOR ------\\

vec2 bsUnionMat(float obj1, float matID1, float obj2, float matID2) {
    if (obj1 < obj2) return vec2(obj1, matID1);
    else             return vec2(obj2, matID2);
}

vec2 smUnionMat(float obj1, float mat1, float obj2, float mat2, float k) {
    float h = clamp ( 0.5 + 0.5*(obj2-obj1)/k, 0.0, 1.0);
    float result = mix(obj2, obj1, h) - k*h*(1.0-h);
    float matblend = mix(mat2, mat1, h);
    return vec2(result , matblend);
}

//------ Rotating Operations ------\\

//input radians
mat2 rot2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c); 
}

//input degrees - can be more intuitive
mat2 degrot2D(float angle) {
    angle = radians(angle);
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c); 
}


// ***** ***** ***** Scene Time ***** ***** *****\\


vec2 map(vec3 pos) {
    float box = sdBox(pos, vec3(0.75));
    vec3 spherePos = vec3( sin(u_time), cos(u_time), 0.0);
    float sphere = sdSphere(pos - spherePos, 0.75);

    return smUnionMat(box, 0.0, sphere, 2.0, 0.1);



}

vec3 getProceduralColor(float id) {
    return 0.5 + 0.5 * cos(id * 1.0 + vec3(0.0, 0.0, 0.0));
}



vec3 getSpecifiedColor(float mat) {
    if (mat == 1.0) return vec3(1.0, 0.0, 0.0); // red 
    if (mat == 2.0) return vec3(0.0, 0.0, 1.0); // blue 
    
    return vec3(0.0); // fallback to black

}

// vec3 calc_normal(vec3 pos) {
//     float e = 0.0001;
//     return normalize(vec3(
//         map(pos + vec3(e, 0, 0)) - map(pos - vec3(e, 0, 0)),
//         map(pos + vec3(0, e, 0)) - map(pos - vec3(0, e, 0)),
//         map(pos + vec3(0, 0, e)) - map(pos - vec3(0, 0, e))
//     ));
// }



// ***** ***** *****  Ray Time  ***** ***** *****\\

vec2 rayMarch(vec3 ray_origin, vec3 ray_dir) {
    float t = 0.;
    float mat = -1.0;

    for (int i = 0; i < u_maxSteps; ++i) {
        vec3 pos = ray_origin + (ray_dir * t);
        vec2 result = map(pos);
        
        if (result.x < u_hitThresh || t > u_maxDist) {
            mat = result.y;
            break;
        }
        t += result.x;
    }
    return vec2(t, mat);
}

void main() {
    vec2 uv = vUv.xy;       
    vec3 ray_origin = u_camPos;                                              // ray origin
    vec3 ray_dir = (u_camInvProjMat * vec4(uv*2. -1., 0, 1)).xyz;            // ray direction
    ray_dir = (u_camToWorldMat * vec4(ray_dir,0)).xyz;
    ray_dir = normalize(ray_dir);
    
    vec2 result = rayMarch(ray_origin, ray_dir); // t is total distance travelled
    float total_dist = result.x;
    float mat = result.y;


    if (total_dist >= u_maxDist || mat <0.0) {
        gl_FragColor = vec4(u_clearColor, 1.0);
    } else {
        vec3 col = getProceduralColor(mat);
        gl_FragColor = vec4(col, 1.0);
    }
}     
