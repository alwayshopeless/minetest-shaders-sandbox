#define rendered texture0
#define bloom texture1

// START unifroms for motion blur
uniform vec2 cameraVelocity;
// END unifroms for motion blur

struct ExposureParams {
	float compensationFactor;
};

uniform sampler2D rendered;
uniform sampler2D bloom;

uniform vec2 texelSize0;

uniform ExposureParams exposureParams;
uniform lowp float bloomIntensity;
uniform lowp float saturation;

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


// START functions for motion blur
float mapValue(float value, float minValue, float maxValue, float newMin, float newMax) {
    return (value - minValue) / (maxValue - minValue) * (newMax - newMin) + newMin;
}


vec4 motionBlur(vec2 realPos, vec4 realCol, vec2 cameraVelocity){
	float Pi = 6.28318530718;
	

    // GAUSSIAN BLUR SETTINGS {{{
    float Directions = 25.0; // BLUR DIRECTIONS (Default 16.0 - More is better but slower)
    float Quality = 16; // BLUR QUALITY (Default 4.0 - More is better but slower)
    float Size = 0.3; // BLUR SIZE (Radius)
    // GAUSSIAN BLUR SETTINGS }}}

    float summaryBrightness = realCol.r + realCol.b + realCol.g;  
	vec2 Radius = Size/vec2(1,1);
	vec4 newCol = realCol;
    for( float d=0.0; d<Pi; d+=Pi/Directions)
    {
		for(float i=0.5/Quality; i<=0.5; i+=0.5/Quality)
        {
			// vec2 tmpPos = realPos+vec2(cos(d),sin(d))*Radius*i;
            			vec2 tmpPos = realPos+vec2(clamp(cameraVelocity.x* 2, -0.1,0.1),clamp(cameraVelocity.y * 2, -0.1,0.1))*Radius*i;
			// tmpPos.t = realPos.t;
                // if (tmpPos.x < 0 || tmpPos.x > 1 || tmpPos.y < 0 || tmpPos.y > 1 ) {
                    // newCol+= realCol;		                    
                // } else {
					vec4 additionalCol = texture2D( texture0, tmpPos); 
					float summaryBrightness = additionalCol.r + additionalCol.b + additionalCol.g;  
					if (summaryBrightness > 2) {
						additionalCol += 0.3;
					}
                    newCol+= additionalCol;		
                // }

        }
    }
    
    // Output to screen
    newCol /= Quality * Directions - 15.0;

    float coeff = 0.9;
    // if (summaryBrightness > 1.1) {
    //     newCol+= 0.8;
    // increase brightness, if it freater then step
    // }
    // return newCol;

	return newCol * coeff + realCol  * (1 - coeff);
}
// END functions for motion blur



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

	if (true) {
		color = motionBlur(uv, color, cameraVelocity);
	}


	gl_FragColor = vec4(color.rgb, 1.0); // force full alpha to avoid holes in the image.
}
