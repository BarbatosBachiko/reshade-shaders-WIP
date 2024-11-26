/*------------------.
| :: Description :: |
'-------------------/

    Ultra Fast Ambient Occlusion (UFAO)
    Author: Barbatos Bachiko
    License: MIT

    About:
    Screen-Space Ambient Occlusion 

    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

    Version 1.0

*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform int viewMode
    <
        ui_type = "combo";
        ui_label = "View Mode";
        ui_tooltip = "Select the view mode for SSAO";
        ui_items = "Normal\0" "AO Only\0";
    > = 0;

uniform float intensity
    <
        ui_type = "slider";
        ui_label = "Occlusion Intensity";
        ui_tooltip = "Adjust the intensity of ambient occlusion";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.05;
    > = 0.1;

uniform float radius
    <
        ui_type = "slider";
        ui_label = "Radius";
        ui_tooltip = "Radius for occlusion sampling";
        ui_min = 0.003; ui_max = 0.01; ui_step = 0.001;
    > = 0.005;

/*---------------.
| :: Textures :: |
'---------------*/
namespace UFAO
{
    texture ColorTex : COLOR;
    texture DepthTex : DEPTH;

    sampler ColorSampler
    {
        Texture = ColorTex;
    };
    sampler DepthSampler
    {
        Texture = DepthTex;
    };

    /*----------------.
    | :: Functions :: |
    '----------------*/

    // Fixed direction vectors for sampling 
    float3 FixedDirection(int sampleIndex)
    {
        if (sampleIndex == 0)
            return float3(1.0, 0.0, 0.0); // Right
        if (sampleIndex == 1)
            return float3(-1.0, 0.0, 0.0); // Left
        if (sampleIndex == 2)
            return float3(0.0, 1.0, 0.0); // Up
        return float3(0.0, -1.0, 0.0); // Down
    }

    // Computes the SSAO 
    float4 SSAO(float2 texcoord)
    {
        float4 originalColor = tex2D(ColorSampler, texcoord);
        float depthValue = tex2D(DepthSampler, texcoord).r;
        float occlusion = 0.0;
        float2 sampleCoords[4];
        
        for (int i = 0; i < 4; i++)
        {
            sampleCoords[i] = texcoord + FixedDirection(i).xy * radius;
        }

        for (int i = 0; i < 4; i++)
        {
            float sampleDepth = tex2D(DepthSampler, sampleCoords[i]).r;
            occlusion += (sampleDepth < depthValue) ? 1.0 : 0.0;
        }

        occlusion *= intensity;

        // View Modes
        if (viewMode == 0)
        {
            return originalColor * (1.0 - occlusion); // Normal View
        }
        else if (viewMode == 1)
        {
            return float4(occlusion, occlusion, occlusion, 1.0); // AO Only
        }
        return originalColor;
    }

    // Pixel Shader
    float4 SSAOPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        return SSAO(texcoord);
    }

    /*-----------------.
    | :: Techniques :: |
    '-----------------*/

    technique UFAO
    {
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = SSAOPS;
        }
    }
}
