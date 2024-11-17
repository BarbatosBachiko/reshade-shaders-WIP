/*------------------.
| :: Description :: |
'-------------------/

    Denoising Shader 

    About:
    This is a basic denoising effect using convolution and blurring techniques.

    Author: Barbatos Bachiko
    License: MIT
*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform float strength < 
    ui_type = "slider";
    ui_label = "Denoise Strength"; 
    ui_tooltip = "Adjust the strength of the denoising effect.";
    ui_min = 0.0; 
    ui_max = 1.0; 
    ui_step = 0.01;
> = 0.5;

/*---------------.
| :: Textures :: |
'---------------*/

// BackBuffer Texture
texture BackBufferTex : COLOR;
sampler BackBuffer
{
    Texture = BackBufferTex;
};

#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)

/*----------------.
| :: Functions :: |
'----------------*/

// Simple Bilateral Filter
float4 DenoiseBilateral(float2 texcoord)
{
    float3 color = tex2D(BackBuffer, texcoord).xyz;
    float3 sum = color;
    float weightSum = 1.0f;
    
    // Filter size
    int filterRadius = 3;
    float sigma_s = 1.5f; 
    float sigma_r = 0.1f; 

    // Sample neighboring pixels
    for (int x = -filterRadius; x <= filterRadius; ++x)
    {
        for (int y = -filterRadius; y <= filterRadius; ++y)
        {
            float2 offset = float2(x, y) * pix;
            float3 neighbor = tex2D(BackBuffer, texcoord + offset).xyz;
            float colorDist = length(color - neighbor);
            float spatialDist = length(float2(x, y));
            float weight = exp(-spatialDist * spatialDist / (2.0f * sigma_s * sigma_s)) *
                           exp(-colorDist * colorDist / (2.0f * sigma_r * sigma_r));

            sum += neighbor * weight;
            weightSum += weight;
        }
    }
    
    
    return float4(sum / weightSum, 1.0f);
}

// PixelShader
void Out(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target)
{
    // Apply bilateral denoising
    float4 denoisedColor = DenoiseBilateral(texcoord);
    
    // Blend original and denoised image based on the strength
    color = lerp(tex2D(BackBuffer, texcoord), denoisedColor, strength);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/

technique Denoise
{
    pass DenoisePass
    {
        VertexShader = PostProcessVS;
        PixelShader = Out;
    }
}
