/*------------------.
| :: Description :: |
'-------------------/

    Ultra Fast Ambient Occlusion (UFAO)
    Author: Barbatos Bachiko
    License: MIT

    About: the only goal is to get maximum performance with ambient occlusion,
    even if the result is kind of meh

    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

    Version 1.2
    + render scale, new texture and code optimization

*/

namespace UFAO
{
#ifndef RENDER_SCALE
#define RENDER_SCALE 0.333
#endif
#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT
#define RENDER_WIDTH (INPUT_WIDTH * RENDER_SCALE)
#define RENDER_HEIGHT (INPUT_HEIGHT * RENDER_SCALE)

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
        ui_items = "Normal\0AO Debug\0Depth\0Sky Debug\0Normal Debug\0";
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

uniform float fDepthMultiplier
    <
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
    > = 0.95;

/*---------------.
| :: Textures :: |
'---------------*/

    texture AOTex
    {
        Width = RENDER_WIDTH;
        Height = RENDER_HEIGHT;
        Format = RGBA8;
    };
    sampler2D sAO
    {
        Texture = AOTex;
    };

    /*----------------.
    | :: Funções ::  |
    '----------------*/

    float GetLinearDepth(float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords) * fDepthMultiplier;
    }
    
    float3 GetNormalFromDepth(float2 coords)
    {
        float2 texelSize = 1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        float depthCenter = GetLinearDepth(coords);
        float depthX = GetLinearDepth(coords + float2(texelSize.x, 0.0));
        float depthY = GetLinearDepth(coords + float2(0.0, texelSize.y));
        float3 deltaX = float3(texelSize.x, 0.0, depthX - depthCenter);
        float3 deltaY = float3(0.0, texelSize.y, depthY - depthCenter);
        float3 normal = normalize(cross(deltaX, deltaY));
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

    float CalculateAO(float2 texcoord)
    {
        float depthValue = GetLinearDepth(texcoord);
        if (depthValue > depthThreshold)
        {
            return 0.0;
        }

        float occlusion = 0.0;
        float2 sampleCoords[4];
        float3 normal = GetNormalFromDepth(texcoord);
        
        for (int i = 0; i < 4; i++)
        {
            sampleCoords[i] = texcoord + FixedDirection(i).xy * radius;
        }

        for (int i = 0; i < 4; i++)
        {
            float sampleDepth = GetLinearDepth(sampleCoords[i]);
            float3 sampleNormal = GetNormalFromDepth(sampleCoords[i]);
            float weight = dot(normal, sampleNormal);
            occlusion += ((sampleDepth < depthValue) && (weight > 0.5)) ? 1.0 : 0.0;
        }

        return occlusion * intensity;
    }

    float4 AO_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
    {
        float2 origTexcoord = texcoord * (1.0 / RENDER_SCALE);
        float ao = CalculateAO(origTexcoord);
        return float4(ao, ao, ao, 1.0);
    }

    float4 Composite_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float4 originalColor = tex2D(ReShade::BackBuffer, uv);
        float ao = tex2D(sAO, uv * RENDER_SCALE).r;
        float depthValue = GetLinearDepth(uv);
        float3 normal = GetNormalFromDepth(uv);
        
        if (viewMode == 0)
        {
            return originalColor * (1.0 - ao); 
        }
        else if (viewMode == 1)
        {
            return float4(ao, ao, ao, 1.0);
        }
        else if (viewMode == 2)
        {
            return float4(depthValue, depthValue, depthValue, 1.0); 
        }
        else if (viewMode == 3)
        {
            return (depthValue >= depthThreshold)
                ? float4(1.0, 0.0, 0.0, 1.0)
                : float4(depthValue, depthValue, depthValue, 1.0);
        }
        else if (viewMode == 4)
        {
            return float4(normal * 0.5 + 0.5, 1.0);
        }
        return originalColor;
    }

    /*-----------------.
    | :: Técnicas ::  |
    '-----------------*/

    technique UFAO
    {
        pass AOPass
        {
            VertexShader = PostProcessVS;
            PixelShader = AO_PS;
            RenderTarget = AOTex;
        }
        pass Composite
        {
            VertexShader = PostProcessVS;
            PixelShader = Composite_PS;
        }
    }
}
