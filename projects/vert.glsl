out vec2 vUv;

void main() {
    // compute view direction in worldspace
    vec4 worldPos = modelViewMatrix * vec4(position, 1.0);
    vec3 viewDir = normalize(-worldPos.xyz);

    // output vertex pos
    gl_Position = projectionMatrix * worldPos;

    vUv = uv;
}