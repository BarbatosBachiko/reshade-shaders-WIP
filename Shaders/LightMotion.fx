/*
# ReshadeMotionEstimation
- Dense Realtime Motion Estimation | Based on Block Matching and Pyramids
- Developed from 2019 to 2022
- First published 2022 - Copyright, Jakob Wapenhensch

# This work is licensed under the Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0) License
- https://creativecommons.org/licenses/by-nc/4.0/
- https://creativecommons.org/licenses/by-nc/4.0/legalcode

# Human-readable summary of the License and not a substitute for https://creativecommons.org/licenses/by-nc/4.0/legalcode:
You are free to:
- Share — copy and redistribute the material in any medium or format
- Adapt — remix, transform, and build upon the material
- The licensor cannot revoke these freedoms as long as you follow the license terms.

Under the following terms:
- Attribution — You must give appropriate credit, provide a link to the license, and indicate if changes were made. You may do so in any reasonable manner, but not in any way that suggests the licensor endorses you or your use.
- NonCommercial — You may not use the material for commercial purposes.
- No additional restrictions — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits.
*/

/*
# LightMotion
- This is a modified version of the "ReshadeMotionEstimation" effect by Jakob Wapenhensch.
- All credits for the core logic and original implementation go to the original author.
- modified by Barbatos
*/


#include "ReShade.fxh"
#include "ReShadeUI.fxh"

//-------------------------------------------|
// :: Preprocessor Definitions & Constants ::|
//-------------------------------------------|

#ifndef PRE_BLOCK_SIZE_2_TO_7
#define PRE_BLOCK_SIZE_2_TO_7	4	//[2 - 7]
#endif

// DO NOT CHANGE THESE
#define BLOCK_SIZE (PRE_BLOCK_SIZE_2_TO_7)
#define BLOCK_SIZE_HALF (int(BLOCK_SIZE / 2))
#define BLOCK_AREA (BLOCK_SIZE * BLOCK_SIZE)

#define ME_PYR_DIVISOR (2)
#define ME_PYR_LVL_1_DIV (ME_PYR_DIVISOR)
#define ME_PYR_LVL_2_DIV (ME_PYR_LVL_1_DIV * ME_PYR_DIVISOR)
#define ME_PYR_LVL_3_DIV (ME_PYR_LVL_2_DIV * ME_PYR_DIVISOR)

// Math Constants
#define M_PI 3.1415926535
#define M_F_R2D (180.f / M_PI)
#define M_F_D2R (1.0 / M_F_R2D)

//----------|
// :: UI :: |
//----------|

// -- Block Matching --
uniform int UI_ME_MAX_ITERATIONS_PER_LEVEL < __UNIFORM_SLIDER_INT1
	ui_min = 1; ui_max = 3; ui_step = 1;
	ui_tooltip = "Select how many Search Iterations are done per Layer. Each Iteration is 2x more precise than the last one.\nHIGH PERFORMANCE IMPACT";
	ui_label = "Search Iterations per Layer";
	ui_category = "Motion Estimation Block Matching";
> = 1;

uniform int UI_ME_SAMPLES_PER_ITERATION < __UNIFORM_SLIDER_INT1
	ui_min = 3; ui_max = 9;ui_step = 1;
	ui_tooltip = "Select how many different Direction are sampled per Iteration.\nHIGH PERFORMANCE IMPACT";
	ui_label = "Samples per Iteration";
	ui_category = "Motion Estimation Block Matching";
> = 3;

// -- Pyramid Upscaling --
uniform float UI_ME_PYRAMID_UPSCALE_FILTER_RADIUS < __UNIFORM_SLIDER_FLOAT1
	ui_min = 3.0; ui_max = 5.0; ui_step = 0.25;
	ui_tooltip = "Select how large the Filter Radius is when Upscaling Vectors from one Layer to the Next.\nNO PERFORMANCE IMPACT";
	ui_label = "Filter Radius";
	ui_category = "Pyramid Upscaling";
> = 3.0;

uniform int UI_ME_PYRAMID_UPSCALE_FILTER_RINGS < __UNIFORM_SLIDER_INT1
	ui_min = 3; ui_max = 5; ui_step = 1;
	ui_tooltip = "Select how many Rings of Samples are taken when Upscaling Vectors from one Layer to the Next.\nMEDIUM PERFORMANCE IMPACT";
	ui_label = "Filter Rings";
	ui_category = "Pyramid Upscaling";
> = 3;

uniform int UI_ME_PYRAMID_UPSCALE_FILTER_SAMPLES_PER_RING < __UNIFORM_SLIDER_INT1
	ui_min = 3; ui_max = 9; ui_step = 1;
	ui_tooltip = "Select how many Samples are taken on the inner most Ring when Upscaling Vectors from one Layer to the Next.\nHIGH PERFORMANCE IMPACT";
	ui_label = "Samples on inner Ring";
	ui_category = "Pyramid Upscaling";
> = 3;

// -- Debug --
uniform bool UI_DEBUG_ENABLE <
	ui_label = "Debug View";
	ui_tooltip = "Activates Debug View";
	ui_category = "Debug";
> = false;

uniform int UI_DEBUG_LAYER < __UNIFORM_SLIDER_INT1
	ui_min = 0; ui_max = 3; ui_step = 1;
	ui_label = "Pyramid Layer";
	ui_tooltip = "Different Layers of the Pyramid. (0=Full, 1=Half, 2=Quarter, 3=Eighth)";
	ui_category = "Debug";
> = 0;

uniform int UI_DEBUG_MODE <
	ui_type = "combo";
	ui_label = "Pyramid Data";
	ui_items = "Gray\0Depth\0Frame Difference\0Feature Level\0Motion\0Final Motion\0Velocity Buffer\0";
	ui_tooltip = "What kind of stuff you wanna see";
	ui_category = "Debug";
> = 5;

uniform int UI_DEBUG_MOTION_ZERO <
	ui_type = "combo";
	ui_label = "Motion Debug Background Color";
	ui_items = "White\0Gray\0Black\0";
	ui_tooltip = "";
	ui_category = "Debug";
> = 1;

uniform float UI_DEBUG_MULT < __UNIFORM_SLIDER_FLOAT1
	ui_min = 1.0; ui_max = 100.0; ui_step = 1;
	ui_tooltip = "Use this if the Debug Output is hard to see";
	ui_label = "Debug Multiplier";
	ui_category = "Debug";
> = 15.0;

uniform int framecount < source = "framecount"; >;

//----------------|
// :: Textures :: |
//----------------|

texture texMotionVectors < pooled = false; >
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG16F;
};
sampler SamplerMotionVectors
{
    Texture = texMotionVectors;
    AddressU = Clamp;
    AddressV = Clamp;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};

// -- Pyramid Level 0 (Full Resolution) --
texture texCur0
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
texture texLast0
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA8;
};
texture texGCur0
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG16F;
};
texture texGLast0
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RG16F;
};
texture texMotionCur0
{
    Width = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = RGBA16F;
};

sampler smpCur0
{
    Texture = texCur0;
};
sampler smpLast0
{
    Texture = texLast0;
};
sampler smpGCur0
{
    Texture = texGCur0;
};
sampler smpGLast0
{
    Texture = texGLast0;
};
sampler smpMCur0
{
    Texture = texMotionCur0;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};

// -- Pyramid Level 1 (Half Resolution) --
texture texGCur1
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_1_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_1_DIV;
    Format = RG16F;
};
texture texGLast1
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_1_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_1_DIV;
    Format = RG16F;
};
texture texMotionCur1
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_1_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_1_DIV;
    Format = RGBA16F;
};

sampler smpGCur1
{
    Texture = texGCur1;
};
sampler smpGLast1
{
    Texture = texGLast1;
};
sampler smpMCur1
{
    Texture = texMotionCur1;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};

// -- Pyramid Level 2 (Quarter Resolution) --
texture texGCur2
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_2_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_2_DIV;
    Format = RG16F;
};
texture texGLast2
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_2_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_2_DIV;
    Format = RG16F;
};
texture texMotionCur2
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_2_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_2_DIV;
    Format = RGBA16F;
};

sampler smpGCur2
{
    Texture = texGCur2;
};
sampler smpGLast2
{
    Texture = texGLast2;
};
sampler smpMCur2
{
    Texture = texMotionCur2;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};

// -- Pyramid Level 3 (Eighth Resolution) --
texture texGCur3
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_3_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_3_DIV;
    Format = RG16F;
};
texture texGLast3
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_3_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_3_DIV;
    Format = RG16F;
};
texture texMotionCur3
{
    Width = BUFFER_WIDTH / ME_PYR_LVL_3_DIV;
    Height = BUFFER_HEIGHT / ME_PYR_LVL_3_DIV;
    Format = RGBA16F;
};

sampler smpGCur3
{
    Texture = texGCur3;
};
sampler smpGLast3
{
    Texture = texGLast3;
};
sampler smpMCur3
{
    Texture = texMotionCur3;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};

  //-------------------|
    // :: Functions  ::|
    //-----------------|

void getBlock(float2 center, out float2 block[BLOCK_AREA], sampler grayIn)
{
    const float2 offsets[16] =
    {
        float2(-2, -2), float2(-1, -2), float2(0, -2), float2(1, -2),
        float2(-2, -1), float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-2, 0), float2(-1, 0), float2(0, 0), float2(1, 0),
        float2(-2, 1), float2(-1, 1), float2(0, 1), float2(1, 1)
    };
    
    [unroll]
    for (int i = 0; i < BLOCK_AREA; i++)
    {
        block[i] = tex2Doffset(grayIn, center, offsets[i]).rg;
    }
}

float getBlockFeatureLevel(float2 block[BLOCK_AREA])
{
    float sum = 0;
    [unroll]
    for (int i = 0; i < BLOCK_AREA; i++)
        sum += block[i].x;
    
    const float average = sum / BLOCK_AREA;
    float diff = 0;
    
    [unroll]
    for (int i = 0; i < BLOCK_AREA; i++)
        diff += abs(block[i].x - average);
    
    return saturate((diff / BLOCK_AREA) * 2);
}

float perPixelLoss(float2 a, float2 b)
{
    float2 loss = abs(a - b);
    return lerp(loss.g, loss.r, 0.75);
}

float blockLoss(float2 a[BLOCK_AREA], float2 b[BLOCK_AREA])
{
    float sum = 0;
    [unroll]
    for (int i = 0; i < BLOCK_AREA; i++)
    {
        sum += perPixelLoss(a[i], b[i]);
    }
    return sum / BLOCK_AREA;
}

float4 packGbuffer(float2 unpackedMotion, float featureLevel, float loss)
{
    return float4(unpackedMotion.x, unpackedMotion.y, featureLevel, loss);
}

float2 motionFromGBuffer(float4 gbuffer)
{
    return gbuffer.rg;
}

float3 HUEtoRGB(in float H)
{
    float R = abs(H * 6.f - 3.f) - 1.f;
    float G = 2.f - abs(H * 6.f - 2.f);
    float B = 2.f - abs(H * 6.f - 4.f);
    return saturate(float3(R, G, B));
}

float3 HSLtoRGB(in float3 HSL)
{
    float3 RGB = HUEtoRGB(HSL.x);
    float C = (1.f - abs(2.f * HSL.z - 1.f)) * HSL.y;
    return (RGB - 0.5f) * C + HSL.z;
}

float4 motionToLgbtq(float2 motion)
{
    float angle = atan2(motion.y, motion.x) * M_F_R2D;
    float dist = length(motion);
    float3 rgb = HSLtoRGB(float3((angle / 360.f) + 0.5, saturate(dist * UI_DEBUG_MULT), 0.5));

    if (UI_DEBUG_MOTION_ZERO == 2)
        rgb = (rgb - 0.5) * 2;
    if (UI_DEBUG_MOTION_ZERO == 0)
        rgb = 1 - ((rgb - 0.5) * 2);
    return float4(rgb.r, rgb.g, rgb.b, 0);
}

float randFloatSeed2(float2 seed)
{
    return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453) * M_PI;
}

float2 getCircleSampleOffset(const int samplesOnCircle, const float radiusInPixels, const int sampleId, const float angleOffset)
{
    float angleDelta = 360.f / samplesOnCircle;
    float sampleAngle = angleOffset + ((angleDelta * sampleId) * M_F_D2R);
    float2 delta = float2(cos(sampleAngle) * radiusInPixels, sin(sampleAngle) * radiusInPixels);
    return delta;
}

// CORE LOGIC 
float4 CalcMotionLayer(float2 coord, float2 searchStart, sampler curBuffer, sampler lastBuffer, const int iterations)
{
    float2 localBlock[BLOCK_AREA];
    getBlock(coord, localBlock, curBuffer);

    float2 searchBlock[BLOCK_AREA];
    getBlock(coord + searchStart, searchBlock, lastBuffer);

    float localLoss = blockLoss(localBlock, searchBlock);
    float localFeatures = getBlockFeatureLevel(localBlock);

    float lowestLoss = localLoss;
    float featuresAtLowestLoss = getBlockFeatureLevel(searchBlock);
    float2 bestMotion = float2(0, 0);
    float2 searchCenter = searchStart;

    float randomValue = randFloatSeed2(coord) * 100;
    randomValue += randFloatSeed2(float2(randomValue, float(framecount % uint(16)))) * 100;
	
    const float2 invTexSize = rcp(tex2Dsize(lastBuffer));

    float searchRadiusDivisor = 1.0;

	[loop]
    for (int i = 0; i < iterations; i++)
    {
        randomValue = randFloatSeed2(float2(randomValue, i * 16)) * 100;
		[loop]
        for (int s = 0; s < UI_ME_SAMPLES_PER_ITERATION; s++)
        {
            float2 pixelOffset = (getCircleSampleOffset(UI_ME_SAMPLES_PER_ITERATION, 1, s, randomValue) * invTexSize) / searchRadiusDivisor;
            float2 samplePos = coord + searchCenter + pixelOffset;
			
            float2 searchBlockB[BLOCK_AREA];
            getBlock(samplePos, searchBlockB, lastBuffer);
            float loss = blockLoss(localBlock, searchBlockB);

			[flatten]
            if (loss < lowestLoss)
            {
                lowestLoss = loss;
                bestMotion = pixelOffset;
                featuresAtLowestLoss = getBlockFeatureLevel(searchBlockB);
            }
        }
        searchCenter += bestMotion;
        bestMotion = float2(0, 0);
        searchRadiusDivisor *= 2.0;
    }
    return packGbuffer(searchCenter, featuresAtLowestLoss, lowestLoss);
}

float4 UpscaleMotion(float2 texcoord, sampler curLevelGray, sampler lowLevelGray, sampler lowLevelMotion)
{
    float localDepth = tex2D(curLevelGray, texcoord).g;
    float summedWeights = 0.0;
    float2 summedMotion = float2(0, 0);
    float summedFeatures = 0.0;
    float summedLoss = 0.0;

    float randomValue = randFloatSeed2(texcoord) * 100;
    randomValue += randFloatSeed2(float2(randomValue, float(framecount % uint(16)))) * 100;
    const float distPerCircle = UI_ME_PYRAMID_UPSCALE_FILTER_RADIUS / UI_ME_PYRAMID_UPSCALE_FILTER_RINGS;
    const float2 invTexSize = rcp(tex2Dsize(lowLevelGray));

	[loop]
    for (int r = 0; r < UI_ME_PYRAMID_UPSCALE_FILTER_RINGS; r++)
    {
        int sampleCount = clamp(UI_ME_PYRAMID_UPSCALE_FILTER_SAMPLES_PER_RING / ((r * 0.5) + 1), 1, UI_ME_PYRAMID_UPSCALE_FILTER_SAMPLES_PER_RING);
        float radius = distPerCircle * (r + 1);
        float circleWeight = 1.0 / (r + 1);
        randomValue += randFloatSeed2(float2(randomValue, r * 10)) * 100;
		[loop]
        for (int i = 0; i < sampleCount; i++)
        {
            float2 samplePos = texcoord + (getCircleSampleOffset(sampleCount, radius, i, randomValue) * invTexSize);
            float nDepth = tex2D(lowLevelGray, samplePos).r;
            float4 llGBuffer = tex2D(lowLevelMotion, samplePos);
            float loss = llGBuffer.a;
            float features = llGBuffer.b;

            float weightDepth = saturate(1.0 - (abs(nDepth - localDepth) * 1));
            float weightLoss = saturate(1.0 - (loss * 1));
            float weightFeatures = saturate((features * 100));
            float weightLength = saturate(1.0 - (length(motionFromGBuffer(llGBuffer) * 1)));
            float weight = saturate(0.000001 + (weightFeatures * weightLoss * weightDepth * weightLength * circleWeight));

            summedWeights += weight;
            summedMotion += motionFromGBuffer(llGBuffer) * weight;
            summedFeatures += features * weight;
            summedLoss += loss * weight;
        }
    }
    return packGbuffer(summedMotion / summedWeights, summedFeatures / summedWeights, summedLoss / summedWeights);
}

    //--------------------|
    // :: Pixel Shaders ::|
    //--------------------|

float4 SaveLastPS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 last : SV_Target1, out float4 lastGray : SV_Target2) : SV_Target0
{
    last = tex2D(smpCur0, texcoord);
    lastGray = tex2D(smpGCur0, texcoord);
    return tex2D(ReShade::BackBuffer, texcoord);
}

float2 CurToGrayPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float gray = dot(tex2D(smpCur0, texcoord).rgb, float3(0.3, 0.5, 0.2));
    float depth = ReShade::GetLinearizedDepth(texcoord);
    return float2(gray, depth);
}

float4 SaveGray1PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    return tex2D(smpGCur1, texcoord);
}
float4 SaveGray2PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    return tex2D(smpGCur2, texcoord);
}
float4 SaveGray3PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target0
{
    return tex2D(smpGCur3, texcoord);
}

float4 DownscaleGray1PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(smpGCur0, texcoord);
}
float4 DownscaleGray2PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(smpGCur1, texcoord);
}
float4 DownscaleGray3PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(smpGCur2, texcoord);
}

float4 MotionEstimation3PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return CalcMotionLayer(texcoord, float2(0, 0), smpGCur3, smpGLast3, UI_ME_MAX_ITERATIONS_PER_LEVEL);
}

float4 MotionEstimation2PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 upscaledLowerLayer = UpscaleMotion(texcoord, smpGCur2, smpGCur3, smpMCur3);
    float2 searchStart = motionFromGBuffer(upscaledLowerLayer);
    return CalcMotionLayer(texcoord, searchStart, smpGCur2, smpGLast2, UI_ME_MAX_ITERATIONS_PER_LEVEL);
}

float4 MotionEstimation1PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 upscaledLowerLayer = UpscaleMotion(texcoord, smpGCur1, smpGCur2, smpMCur2);
    float2 searchStart = motionFromGBuffer(upscaledLowerLayer);
    return CalcMotionLayer(texcoord, searchStart, smpGCur1, smpGLast1, UI_ME_MAX_ITERATIONS_PER_LEVEL);
}

float4 MotionEstimation0PS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return UpscaleMotion(texcoord, smpGCur0, smpGCur1, smpMCur1);
}

float2 MotionOutputPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return tex2D(smpMCur0, texcoord).rg;
}

float4 OutputPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (UI_DEBUG_ENABLE)
    {
        float4 returnValue = 0;
        switch (UI_DEBUG_MODE)
        {
            case 0: // Grayscale
                switch (UI_DEBUG_LAYER)
                {
                    case 0:
                        returnValue = tex2D(smpGCur0, texcoord).r;
                        break;
                    case 1:
                        returnValue = tex2D(smpGCur1, texcoord).r;
                        break;
                    case 2:
                        returnValue = tex2D(smpGCur2, texcoord).r;
                        break;
                    case 3:
                        returnValue = tex2D(smpGCur3, texcoord).r;
                        break;
                }
                break;
            case 1: // Depth
                switch (UI_DEBUG_LAYER)
                {
                    case 0:
                        returnValue = tex2D(smpGCur0, texcoord).g;
                        break;
                    case 1:
                        returnValue = tex2D(smpGCur1, texcoord).g;
                        break;
                    case 2:
                        returnValue = tex2D(smpGCur2, texcoord).g;
                        break;
                    case 3:
                        returnValue = tex2D(smpGCur3, texcoord).g;
                        break;
                }
                break;
            case 2: // Frame Difference
                switch (UI_DEBUG_LAYER)
                {
                    case 0:
                        returnValue = abs(tex2D(smpGCur0, texcoord).r - tex2D(smpGLast0, texcoord)).r;
                        break;
                    case 1:
                        returnValue = abs(tex2D(smpGCur1, texcoord).r - tex2D(smpGLast1, texcoord)).r;
                        break;
                    case 2:
                        returnValue = abs(tex2D(smpGCur2, texcoord).r - tex2D(smpGLast2, texcoord)).r;
                        break;
                    case 3:
                        returnValue = abs(tex2D(smpGCur3, texcoord).r - tex2D(smpGLast3, texcoord)).r;
                        break;
                }
                break;
            case 3: // Feature Level
				{
                    float2 block[BLOCK_AREA];
                    switch (UI_DEBUG_LAYER)
                    {
                        case 0:
                            getBlock(texcoord, block, smpGCur0);
                            returnValue = getBlockFeatureLevel(block);
                            break;
                        case 1:
                            getBlock(texcoord, block, smpGCur1);
                            returnValue = getBlockFeatureLevel(block);
                            break;
                        case 2:
                            getBlock(texcoord, block, smpGCur2);
                            returnValue = getBlockFeatureLevel(block);
                            break;
                        case 3:
                            getBlock(texcoord, block, smpGCur3);
                            returnValue = getBlockFeatureLevel(block);
                            break;
                    }
                }
                break;
            case 4: // Motion
                switch (UI_DEBUG_LAYER)
                {
                    case 0:
                        returnValue = motionToLgbtq(motionFromGBuffer(tex2D(smpMCur0, texcoord)));
                        break;
                    case 1:
                        returnValue = motionToLgbtq(motionFromGBuffer(tex2D(smpMCur1, texcoord)));
                        break;
                    case 2:
                        returnValue = motionToLgbtq(motionFromGBuffer(tex2D(smpMCur2, texcoord)));
                        break;
                    case 3:
                        returnValue = motionToLgbtq(motionFromGBuffer(tex2D(smpMCur3, texcoord)));
                        break;
                }
                break;
            case 5: // Final Motion
                returnValue = motionToLgbtq(tex2D(SamplerMotionVectors, texcoord).rg);
                break;
            case 6: // Velocity Buffer
                returnValue = float4(((tex2D(SamplerMotionVectors, texcoord).rg * 0.5 * UI_DEBUG_MULT) + 0.5), 0, 0);
                break;
        }
        return returnValue;
    }
    else
    {
        return tex2D(ReShade::BackBuffer, texcoord);
    }
}

//--------------------------------------------------------------------------------------
// :: TECHNIQUE ::
//--------------------------------------------------------------------------------------

technique LightMotion
{
    pass SaveLastColorPass
    {
        VertexShader = PostProcessVS;
        PixelShader = SaveLastPS;
        RenderTarget0 = texCur0;
        RenderTarget1 = texLast0;
        RenderTarget2 = texGLast0;
    }
    pass SaveGray1Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = SaveGray1PS;
        RenderTarget0 = texGLast1;
    }
    pass SaveGray2Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = SaveGray2PS;
        RenderTarget0 = texGLast2;
    }
    pass SaveGray3Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = SaveGray3PS;
        RenderTarget0 = texGLast3;
    }
	
    pass MakeGrayPass
    {
        VertexShader = PostProcessVS;
        PixelShader = CurToGrayPS;
        RenderTarget = texGCur0;
    }
	
    pass DownscaleGray1Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = DownscaleGray1PS;
        RenderTarget = texGCur1;
    }
    pass DownscaleGray2Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = DownscaleGray2PS;
        RenderTarget = texGCur2;
    }
    pass DownscaleGray3Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = DownscaleGray3PS;
        RenderTarget = texGCur3;
    }

    pass MotionEstimation3Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionEstimation3PS;
        RenderTarget = texMotionCur3;
    }
    pass MotionEstimation2Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionEstimation2PS;
        RenderTarget = texMotionCur2;
    }
    pass MotionEstimation1Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionEstimation1PS;
        RenderTarget = texMotionCur1;
    }
    pass MotionEstimation0Pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionEstimation0PS;
        RenderTarget = texMotionCur0;
    }
    pass MotionOutputPass
    {
        VertexShader = PostProcessVS;
        PixelShader = MotionOutputPS;
        RenderTarget = texMotionVectors;
    }
    pass OutputPass
    {
        VertexShader = PostProcessVS;
        PixelShader = OutputPS;
    }
}
