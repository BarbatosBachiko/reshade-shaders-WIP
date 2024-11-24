/*------------------.
| :: Description :: |
'-------------------/

    Upscaling (version 1.0)

    Author: Barbatos Bachiko
    Original by Jakob Wapenhensch from (https://github.com/JakobPCoder/ReshadeBUR)
    
    License: CC BY-NC-SA 4.0 DEED (https://creativecommons.org/licenses/by-nc-sa/4.0/)

    About:
    This shader provides a system for resampling and spatial upscaling with options for different upscaling methods.

    Ideas for future improvement:
    * Add support for more upscaling techniques.
    * Implement custom sharpening filters for more control.

    History:
    (*) Feature (+) Improvement    (x) Bugfix    (-) Information    (!) Compatibility
    
    Version 1.0
    * Initial release with Mitchell-Netravali resampling and BCAS, xBR, Super-Resolution-Like upscaling.

*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShadeUI.fxh"
#include "ReShade.fxh"
#include "BUR_fsr1.fxh"

/*---------------.
|  :: DEFINES :: |
'---------------*/

// RATIO_WIDTH and RATIO_HEIGHT define the scaling factors for the width and height of the image
// RATIO_WIDTH and RATIO_HEIGHT should be screen res / game render res
#ifndef RATIO_WIDTH
#define RATIO_WIDTH 	  	0.5 // Default scaling factor for width is 0.5 (50%)
#endif

#ifndef RATIO_HEIGHT
#define RATIO_HEIGHT 	  	0.5 // Default scaling factor for height is 0.5 (50%)		
#endif

// Undefine DONT_CHANGE_X and DONT_CHANGE_Y to ensure they are not already defined
#ifdef DONT_CHANGE_X
#undef DONT_CHANGE_X 
#endif
#ifdef DONT_CHANGE_Y
#undef DONT_CHANGE_Y 
#endif

// DONT_CHANGE_X and DONT_CHANGE_Y define the dimensions of the output image
#ifndef DONT_CHANGE_X
#define DONT_CHANGE_X BUFFER_WIDTH * RATIO_WIDTH
#endif

#ifndef DONT_CHANGE_Y
#define DONT_CHANGE_Y BUFFER_HEIGHT * RATIO_HEIGHT
#endif

// Convenience defines for the scaling factors and output resolution
#define RATIO float2(RATIO_WIDTH, RATIO_HEIGHT)
#define ORIGINAL_RES float2(DONT_CHANGE_X, DONT_CHANGE_Y)

/*---------------.
| :: Settings :: |
'---------------*/

uniform int UI_RESAMPLE_METHOD < 
    ui_type = "combo";
    ui_label = "Resampling Method";
    ui_items = "Point\0Linear\0Cubic\0Mitchell-Netravali\0"; 
    ui_tooltip = "Select sample method used to resample the badly upscaled original image.\nThis should ideally match the method used by the game to upscale the image.";
    ui_category = "Resampling Method";
> = 4;

uniform int UI_SPATIAL_UPSCALER < 
	ui_type = "combo";
	ui_label = "Spatial Upscaling Method";
	ui_items = "EASU (FSR 1.0)\0BCAS\0xBR\0Super Resolution\0"; 
	ui_tooltip = "Select the spatial upscaler to use.";
	ui_category = "Spatial Upscaling";
> = 0;

uniform int UI_POST_SHARP <
	ui_type = "combo";
    ui_label = "Post Sharpening Method";
	ui_items = "OFF\0RCAS (FSR 1.0)\0";
	ui_tooltip = "Select the post upscaler sharpening method to use after upscaling.";
    ui_category = "Post";
> = 1;

uniform float UI_POST_SHARP_STRENGTH < __UNIFORM_DRAG_FLOAT1
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.1;
	ui_tooltip = "Sharpening strength";
	ui_label = "Set the amount of sharpening to apply to the image after upscaling.";
    ui_category = "Post";
> = 0.5;

uniform int framecount < source = "framecount"; >;


/*---------------.
| :: Textures :: |
'---------------*/

// Textures
texture2D texColorBuffer : COLOR;
texture2D lowRedBaseTex
{
    Width = int(DONT_CHANGE_X);
    Height = int(DONT_CHANGE_Y);
    Format = RGBA8;
};

// Samplers
sampler2D colorSamplerPoint
{
    Texture = texColorBuffer;
    AddressU = BORDER;
    AddressV = BORDER;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};
sampler2D colorSamplerLinear
{
    Texture = texColorBuffer;
    AddressU = BORDER;
    AddressV = BORDER;
    MipFilter = Linear;
    MinFilter = Linear;
    MagFilter = Linear;
};

sampler2D lowResColorPointSampler
{
    Texture = lowRedBaseTex;
    AddressU = BORDER;
    AddressV = BORDER;
    MipFilter = Point;
    MinFilter = Point;
    MagFilter = Point;
};
sampler2D lowResColorLinearSampler
{
    Texture = lowRedBaseTex;
    AddressU = BORDER;
    AddressV = BORDER;
    MipFilter = Linear;
    MinFilter = Linear;
    MagFilter = Linear;
};

/*----------------.
| :: Functions :: |
'----------------*/

float4 sampleBicubic(sampler2D source, float2 texcoord)
{
	// Calculate the size of the source texture
    float2 texSize = tex2Dsize(source);

    // Calculate the position to sample in the source texture
    float2 samplePos = texcoord * texSize;

    // Calculate the integer and fractional parts of the sample position
    float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;
    float2 f = samplePos - texPos1;

    // Calculate the interpolation weights for the four cubic spline basis functions
    float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
    float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
    float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
    float2 w3 = 1.0f - (w0 + w1 + w2);

    // Calculate weights for two intermediate values (used for more efficient sampling)
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / w12;

    // Calculate the positions to sample for the eight texels involved in bicubic interpolation
    float2 texPos0 = texPos1 - 1;
    float2 texPos3 = texPos1 + 2;
    float2 texPos12 = texPos1 + offset12;

    // Normalize the texel positions to the [0, 1] range
    texPos0 /= texSize;
    texPos3 /= texSize;
    texPos12 /= texSize;

    // Initialize the result variable, for accumulating the weighted samples
    float4 result = 0.0f;

    // Perform bicubic interpolation by sampling the source texture linearly
    // with the calculated weights at the calculated positions
    result += tex2Dlod(source, float4(texPos0.x, texPos0.y, 0, 0)) * w0.x * w0.y;
    result += tex2Dlod(source, float4(texPos12.x, texPos0.y, 0, 0)) * w12.x * w0.y;
    result += tex2Dlod(source, float4(texPos3.x, texPos0.y, 0, 0)) * w3.x * w0.y;

    result += tex2Dlod(source, float4(texPos0.x, texPos12.y, 0, 0)) * w0.x * w12.y;
    result += tex2Dlod(source, float4(texPos12.x, texPos12.y, 0, 0)) * w12.x * w12.y;
    result += tex2Dlod(source, float4(texPos3.x, texPos12.y, 0, 0)) * w3.x * w12.y;

    result += tex2Dlod(source, float4(texPos0.x, texPos3.y, 0, 0)) * w0.x * w3.y;
    result += tex2Dlod(source, float4(texPos12.x, texPos3.y, 0, 0)) * w12.x * w3.y;
    result += tex2Dlod(source, float4(texPos3.x, texPos3.y, 0, 0)) * w3.x * w3.y;

    return result;
}

float4 sampleFSR1(sampler2D source, float2 texcoord)
{
    float4 con0, con1, con2, con3;
    FsrEasuCon(con0, con1, con2, con3, ORIGINAL_RES, ORIGINAL_RES, ReShade::ScreenSize);
    float3 c = FsrEasuF(source, (texcoord * ReShade::ScreenSize) + (1.0 - RATIO), con0, con1, con2, con3);
    return float4(c.rgb, 1);
}

float4 sampleBCAS(sampler2D source, float2 texcoord)
{
    // Define a contrast-aware kernel size (this can be adjusted for better results)
    float kernelSize = 5.0f;
    float contrastThreshold = 0.1f;

    // Get the original texel color
    float4 centerColor = tex2D(source, texcoord);

    // Initialize variables for accumulated color and weight
    float4 accumulatedColor = 0.0f;
    float accumulatedWeight = 0.0f;

    // Loop through the surrounding pixels in a kernel around the center
    for (int y = -2; y <= 2; ++y)
    {
        for (int x = -2; x <= 2; ++x)
        {
            float2 offset = float2(x, y) / ReShade::ScreenSize;
            float4 neighborColor = tex2D(source, texcoord + offset);

            // Compute the contrast between the center and the neighbor
            float contrast = max(abs(centerColor.r - neighborColor.r), max(abs(centerColor.g - neighborColor.g), abs(centerColor.b - neighborColor.b)));

            // Apply a weighting function based on contrast (only neighbors with low contrast are weighted more)
            float weight = exp(-contrast / contrastThreshold);
            accumulatedColor += neighborColor * weight;
            accumulatedWeight += weight;
        }
    }

    // Normalize the accumulated color by the total weight
    return accumulatedColor / accumulatedWeight;
}

float4 sampleXBR(sampler2D source, float2 texcoord)
{
    // Scale texcoord to source texture size
    float2 texSize = tex2Dsize(source);
    float2 samplePos = texcoord * texSize;

    // Get the integer part of the position (current texel)
    float2 texel = floor(samplePos);
    
    // Compute the fractional part (used for blending)
    float2 frac = frac(samplePos);

    // Sample neighboring pixels (4 nearest neighbors)
    float4 c00 = tex2Dlod(source, float4((texel + float2(0, 0)) / texSize, 0, 0));
    float4 c10 = tex2Dlod(source, float4((texel + float2(1, 0)) / texSize, 0, 0));
    float4 c01 = tex2Dlod(source, float4((texel + float2(0, 1)) / texSize, 0, 0));
    float4 c11 = tex2Dlod(source, float4((texel + float2(1, 1)) / texSize, 0, 0));

    // Detect edges based on color difference
    float2 edgeDetect = abs(c00.rgb - c11.rgb) - abs(c10.rgb - c01.rgb);

    // Blend based on edge presence and fractional position
    float2 weight = smoothstep(0.0, 1.0, frac) * (1.0 - smoothstep(-1.0, 0.0, edgeDetect));
    float4 blended = lerp(lerp(c00, c10, weight.x), lerp(c01, c11, weight.x), weight.y);

    return blended;
}

float4 sampleSuperResolution(sampler2D source, float2 texcoord)
{
    // Calculate the size of the source texture
    float2 texSize = tex2Dsize(source);
    
    // Perform bicubic interpolation 
    float2 texPos = texcoord * texSize;
    float2 texPos_floor = floor(texPos);
    float2 texPos_frac = frac(texPos);
    
    float4 c00 = tex2Dlod(source, float4((texPos_floor + float2(0, 0)) / texSize, 0, 0));
    float4 c10 = tex2Dlod(source, float4((texPos_floor + float2(1, 0)) / texSize, 0, 0));
    float4 c01 = tex2Dlod(source, float4((texPos_floor + float2(0, 1)) / texSize, 0, 0));
    float4 c11 = tex2Dlod(source, float4((texPos_floor + float2(1, 1)) / texSize, 0, 0));
    
    // Perform bicubic interpolation (basic 2x2)
    float4 color_x0 = lerp(c00, c10, texPos_frac.x);
    float4 color_x1 = lerp(c01, c11, texPos_frac.x);
    float4 bicubicColor = lerp(color_x0, color_x1, texPos_frac.y);
    
    // Edge enhancement using contrast-aware sharpening
    float contrastThreshold = 0.02;
    float4 centerColor = tex2Dlod(source, float4(texcoord, 0, 0));

    // Calculate the contrast between the center and its neighbors
    float contrast = 0.0;
    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            // Avoid sampling the center pixel
            if (x == 0 && y == 0)
                continue;
            
            // Ensure the coordinates are within bounds
            float2 offset = float2(x, y) / texSize;
            float2 neighborCoord = texcoord + offset;
            neighborCoord = clamp(neighborCoord, float2(0.0, 0.0), float2(1.0, 1.0));
            
            float4 neighborColor = tex2D(source, neighborCoord);
            
            // Calculate contrast with each neighbor
            contrast += max(abs(centerColor.r - neighborColor.r),
                            max(abs(centerColor.g - neighborColor.g),
                            abs(centerColor.b - neighborColor.b)));
        }
    }
    
    // Apply sharpening based on contrast
    float sharpenFactor = 2.0;
    if (contrast > contrastThreshold)
    {
        bicubicColor += sharpenFactor * (centerColor - bicubicColor);
    }

    return bicubicColor;
}

// Mitchell-Netravali resampling kernel
// B = 1/3, C = 1/3 gives a good balance between sharpness and smoothness
float MitchellNetravaliKernel(float x, float B, float C)
{
    float absX = abs(x);
    if (absX < 1.0)
    {
        return ((12 - 9 * B - 6 * C) * pow(absX, 3) + (27 - 21 * B - 15 * C) * pow(absX, 2) + (8 * B + 12 * C) * absX) / 6.0;
    }
    else if (absX < 2.0)
    {
        return ((-B - 6 * C) * pow(absX, 3) + (6 * B + 30 * C) * pow(absX, 2) + (-12 * B - 48 * C) * absX + (8 * B + 24 * C)) / 6.0;
    }
    else
    {
        return 0.0;
    }
}

// Mitchell-Netravali resampling function
float4 sampleMitchellNetravali(sampler2D source, float2 texcoord, float B, float C)
{
    float2 texSize = tex2Dsize(source);
    float2 samplePos = texcoord * texSize;
    
    float2 texPos_floor = floor(samplePos);
    float2 texPos_frac = frac(samplePos);

    // Accumulate the weighted color values
    float4 result = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float weightSum = 0.0f;

    // Sample the surrounding pixels using the Mitchell-Netravali kernel
    for (int y = -2; y <= 2; ++y)
    {
        for (int x = -2; x <= 2; ++x)
        {
            // Calculate the distance from the current texel position
            float2 offset = float2(x, y);
            float2 texPos = texPos_floor + offset;
            float2 dist = texPos - samplePos;
            float weight = MitchellNetravaliKernel(dist.x, B, C) * MitchellNetravaliKernel(dist.y, B, C);

            result += tex2D(source, texPos / texSize) * weight;
            weightSum += weight;
        }
    }

    return result / weightSum;
}

/*-----------------.
|  ::  Passes   :: |
'-----------------*/

//Retarget the content from the low res resampled texture to the top left corner of the native screen buffer.
float4 RetargetColor(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    // Divide texture coordinates by RATIO to get coordinates for upscaled image
    float2 coords = texcoord / RATIO;

    float4 color = 0;
    // Switch statement to select resampling method
    switch (UI_RESAMPLE_METHOD)
    {
        case 0:
            // Point sampling
            color = tex2Dlod(colorSamplerPoint, float4(coords, 0, 0));
            break;
        case 1:
            // Bilinear filtering
            color = tex2Dlod(colorSamplerLinear, float4(coords, 0, 0));
            break;
        case 2:
            // Bicubic filtering
            color = sampleBicubic(colorSamplerLinear, coords);
            break;
        case 3:
            // Mitchell-Netravali resampling
            color = sampleMitchellNetravali(colorSamplerLinear, coords, 1.0f / 3.0f, 1.0f / 3.0f); // B = 1/3, C = 1/3
            break;
        default:
            // Default to point sampling if invalid method selected
            color = tex2Dlod(colorSamplerPoint, float4(coords, 0, 0));
            break;
    }
    // Return upscaled color
    return color;
}

//Save the content from the top left corner of the native screen buffer to a texture of the size of that area.
float4 SaveLowResPostFX(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float2 coords = texcoord * ReShade::ScreenSize * RATIO;
    return tex2Dfetch(colorSamplerPoint, int2(coords));
}

//Upscale the content of the low res texture to the native screen buffer.
float4 UpscalingMain(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = 0;
    switch (UI_SPATIAL_UPSCALER)
    {
        case 0:
            color = sampleFSR1(lowResColorLinearSampler, texcoord);
            break;
        case 1:
            color = sampleBCAS(lowResColorLinearSampler, texcoord);
            break;
        case 2:
            color = sampleXBR(lowResColorLinearSampler, texcoord);
            break;
        case 3:
            color = sampleSuperResolution(lowResColorLinearSampler, texcoord);
            break;
    }
    return color;
}


//Apply post processing effects to the upscaled content.
float4 UpscalingPost(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 color = 0;
    switch (UI_POST_SHARP)
    {
        case 1:
            float base = 8;
            float sharpeness = ((base + 0.1) - (sqrt(sqrt(UI_POST_SHARP_STRENGTH)) * base)) * RATIO;
            color = Rcas(colorSamplerLinear, texcoord, sharpeness);
            break;
        default:
            color = tex2Dlod(colorSamplerPoint, float4(texcoord, 0, 0));
            break;
    }

    return color;
}

/*-----------------.
| :: Techniques :: |
'-----------------*/

technique BUR_1_Prepass < ui_tooltip = "This is an example!"; >
{
    pass P1_Resample
    {
        VertexShader = PostProcessVS;
        PixelShader = RetargetColor;
    }
}

technique BUR_2_Upscaling < ui_tooltip = "This is an example!"; >
{
    pass P2_save_low_res
    {
        VertexShader = PostProcessVS;
        PixelShader = SaveLowResPostFX;
        RenderTarget = lowRedBaseTex;
    }

    pass P3_upsampling_main
    {
        VertexShader = PostProcessVS;
        PixelShader = UpscalingMain;
    }
  
    pass P4_upsampling_post
    {
        VertexShader = PostProcessVS;
        PixelShader = UpscalingPost;
    }
}
