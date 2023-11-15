#define rendered texture0
#define bloom texture1

struct ExposureParams {
	float compensationFactor;
};

uniform sampler2D rendered;
uniform sampler2D bloom;

uniform vec2 texelSize0;

uniform ExposureParams exposureParams;
uniform lowp float bloomIntensity;
uniform lowp float saturation;

//waterdrops
uniform float time;

//end waterdrops


#ifdef GL_ES
varying mediump vec2 varTexCoord;
#else
centroid varying vec2 varTexCoord;
#endif

#ifdef ENABLE_AUTO_EXPOSURE
varying float exposure; // linear exposure factor, see vertex shader
#endif

#ifdef ENABLE_BLOOM

vec4 applyBloom(vec4 color, vec2 uv)
{
	vec3 light = texture2D(bloom, uv).rgb;
#ifdef ENABLE_BLOOM_DEBUG
	if (uv.x > 0.5 && uv.y < 0.5)
		return vec4(light, color.a);
	if (uv.x < 0.5)
		return color;
#endif
	color.rgb = mix(color.rgb, light, bloomIntensity);
	return color;
}

#endif

#if ENABLE_TONE_MAPPING

/* Hable's UC2 Tone mapping parameters
	A = 0.22;
	B = 0.30;
	C = 0.10;
	D = 0.20;
	E = 0.01;
	F = 0.30;
	W = 11.2;
	equation used:  ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F
*/

vec3 uncharted2Tonemap(vec3 x)
{
	return ((x * (0.22 * x + 0.03) + 0.002) / (x * (0.22 * x + 0.3) + 0.06)) - 0.03333;
}

vec4 applyToneMapping(vec4 color)
{
	const float exposureBias = 2.0;
	color.rgb = uncharted2Tonemap(exposureBias * color.rgb);
	// Precalculated white_scale from
	//vec3 whiteScale = 1.0 / uncharted2Tonemap(vec3(W));
	vec3 whiteScale = vec3(1.036015346);
	color.rgb *= whiteScale;
	return color;
}

vec3 applySaturation(vec3 color, float factor)
{
	// Calculate the perceived luminosity from the RGB color.
	// See also: https://www.w3.org/WAI/GL/wiki/Relative_luminance
	float brightness = dot(color, vec3(0.2125, 0.7154, 0.0721));
	return mix(vec3(brightness), color, factor);
}
#endif



// waterdrops func start


vec2 hash22(vec2 p){
    vec2 p2 = fract(p * vec2(.1031,.1030));
    p2 += dot(p2, p2.yx+19.19);
    return fract((p2.x+p2.y)*p2);
}
#define round(x) floor( (x) + .5 )

float simplex2D(vec2 p ){
    const float K1 = (sqrt(3.)-1.)/2.;
    const float K2 = (3.-sqrt(3.))/6.;
    const float K3 = K2*2.;

    vec2 i = floor( p + dot(p,vec2(K1)) );
    
    vec2 a = p - i + dot(i,vec2(K2));
    vec2 o = 1.-clamp((a.yx-a)*1.e35,0.,1.);
    vec2 b = a - o + K2;
    vec2 c = a - 1.0 + K3;

    vec3 h = clamp( .5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0. ,1. );
    
    h*=h;
    h*=h;

    vec3 n = vec3( 
        dot(a,hash22(i   )-.5),
        dot(b,hash22(i+o )-.5),
        dot(c,hash22(i+1.)-.5)
    );

    return dot(n,h)*140.;
}


vec2 wetGlass(vec2 p) {
    
    p += simplex2D(p*0.1) * 3.; // distort drops
    
    float t = time / 500000;
    
    p *= vec2(.025, .025 * .25);
    
    p.y += t * .25; // make drops fall
    
    vec2 rp = round(p);
    vec2 dropPos = p - rp;
    vec2 noise = hash22(rp);
    
    dropPos.y *= 4.;
    
    t = t * noise.y + (noise.x*6.28);
    
    vec2 trailPos = vec2(dropPos.x, fract((dropPos.y-t)*2.) * .5 - .25 );
    
    dropPos.y += cos( t + cos(t) );  // make speed vary
   
    float trailMask = clamp(dropPos.y*2.5+.5,0.,1.); // hide trail in front of drop

    float dropSize  = dot(dropPos,dropPos);
    
    float trailSize = clamp(trailMask*dropPos.y-0.5,0.,1.) + 0.5;
    trailSize = dot(trailPos,trailPos) * trailSize * trailSize;
    
    float drop  = clamp(dropSize  * -60.+ 3.*noise.y, 0., 1.);
    float trail = clamp(trailSize * -60.+ .5*noise.y, 0., 1.);
    
    trail *= trailMask; // hide trail in front of drop
    
    return drop * dropPos + trailPos * trail;
} 

//waterdrops end



void main(void)
{
	vec2 uv = varTexCoord.st;
#ifdef ENABLE_SSAA
	vec4 color = vec4(0.);
	for (float dx = 1.; dx < SSAA_SCALE; dx += 2.)
	for (float dy = 1.; dy < SSAA_SCALE; dy += 2.)
		color += texture2D(rendered, uv + texelSize0 * vec2(dx, dy)).rgba;
	color /= SSAA_SCALE * SSAA_SCALE / 4.;
#else
	vec4 color = texture2D(rendered, uv).rgba;
#endif

	// translate to linear colorspace (approximate)
	color.rgb = pow(color.rgb, vec3(2.2));

#ifdef ENABLE_BLOOM_DEBUG
	if (uv.x > 0.5 || uv.y > 0.5)
#endif
	{
		color.rgb *= exposureParams.compensationFactor;
#ifdef ENABLE_AUTO_EXPOSURE
		color.rgb *= exposure;
#endif
	}


#ifdef ENABLE_BLOOM
	color = applyBloom(color, uv);
#endif

#ifdef ENABLE_BLOOM_DEBUG
	if (uv.x > 0.5 || uv.y > 0.5)
#endif
	{
#if ENABLE_TONE_MAPPING
		color = applyToneMapping(color);
		color.rgb = applySaturation(color.rgb, saturation);
#endif
	}

	color.rgb = clamp(color.rgb, vec3(0.), vec3(1.));

	// return to sRGB colorspace (approximate)
	color.rgb = pow(color.rgb, vec3(1.0 / 2.2));

//waterdrops
vec2 realPos = varTexCoord.st;
vec4 realCol = color;
realPos += wetGlass(gl_FragCoord.xy);
color = texture2D(texture0, realPos);
//end waterdrops
	gl_FragColor = vec4(color.rgb, 1.0); // force full alpha to avoid holes in the image.
}
