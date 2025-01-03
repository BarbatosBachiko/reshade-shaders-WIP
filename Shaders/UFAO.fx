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

    Version 1.1
    + yet

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

uniform float fDepthMultiplier <
        ui_type = "slider";
        ui_category = "Depth";
        ui_label = "Depth multiplier";
        ui_min = 0.001; ui_max = 20.00;
        ui_step = 0.001;
    > = 1.0;

uniform float depthThreshold
<
    ui_type = "slider";
    ui_category = "Depth";
    ui_label = "Depth Threshold (Sky)";
    ui_tooltip = "Set the depth threshold to ignore the sky during occlusion.";
    ui_min = 0.9; ui_max = 1.0; ui_step = 0.01;
>
= 0.95;

/*---------------.
| :: Textures :: |
'---------------*/
namespace UFAO
{
    texture ColorTex : COLOR;
    texture DepthTex : DEPTH;
    texture NormalTex : NORMAL;
    sampler ColorSampler
    {
        Texture = ColorTex;
    };
    sampler DepthSampler
    {
        Texture = DepthTex;
    };
    sampler NormalSampler
    {
        Texture = NormalTex;
    };
    
    /*----------------.
    | :: Functions :: |
    '----------------*/

    float GetLinearDepth(float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords) * fDepthMultiplier;
    }
    
    float3 GetNormal(float2 coords)
    {
        float4 normalTex = tex2D(NormalSampler, coords);
        float3 normal = normalize(normalTex.xyz * 2.0 - 1.0);
        return normal;
    }
    
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

    float4 SSAO(float2 texcoord)
    {
        float4 originalColor = tex2D(ColorSampler, texcoord);
        float depthValue = GetLinearDepth(texcoord);

        if (depthValue > depthThreshold)
        {
            return originalColor;
        }

        float occlusion = 0.0;
        float2 sampleCoords[4];
        float3 normal = GetNormal(texcoord);
        
        for (int i = 0; i < 4; i++)
        {
            sampleCoords[i] = texcoord + FixedDirection(i).xy * radius;
        }

        for (int i = 0; i < 4; i++)
        {
            float sampleDepth = GetLinearDepth(sampleCoords[i]);
            float3 sampleNormal = GetNormal(sampleCoords[i]);
            float weight = dot(normal, sampleNormal);
            occlusion += ((sampleDepth < depthValue) && (weight > 0.5)) ? 1.0 : 0.0;
        }

        occlusion *= intensity;

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
