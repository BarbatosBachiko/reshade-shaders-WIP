/*------------------.
| :: Description :: |
'-------------------/
 
    NeoFog
    Version 1.0
    Author: Barbatos Bachiko
    License: MIT

    About: Screen Space Fog.
*/

namespace NEOFog
{
#define INPUT_WIDTH BUFFER_WIDTH 
#define INPUT_HEIGHT BUFFER_HEIGHT 

#ifndef RES_SCALE
#define RES_SCALE 0.888
#endif
#define RES_WIDTH (INPUT_WIDTH * RES_SCALE)
#define RES_HEIGHT (INPUT_HEIGHT * RES_SCALE) 

    /*-------------------.
    | :: Includes ::    |
    '-------------------*/
#include "ReShade.fxh"

    /*-------------------.
    | :: Settings ::    |
    '-------------------*/

    uniform int ViewMode
    <
        ui_category = "General";
        ui_type = "combo";
        ui_label = "View Mode";
        ui_tooltip = "Select the view mode for Fog";
        ui_items = "Normal\0Fog Debug\0Depth\0Sky Debug\0";
    >
    = 0;

    uniform float FogIntensity
    <
        ui_category = "General";
        ui_type = "slider";
        ui_label = "Fog Intensity";
        ui_min = 0.0; ui_max = 20.0; ui_step = 0.01;
    >
    = 10.0;

    uniform float FogStart
    <
        ui_category = "Fog";
        ui_type = "slider";
        ui_label = "Fog Start";
        ui_tooltip = "Distance at which fog starts to appear.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 0.0;

    uniform float FogEnd
    <
        ui_category = "Fog";
        ui_type = "slider";
        ui_label = "Fog End";
        ui_tooltip = "Distance at which fog is fully opaque.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 1.0;
    
    uniform float DepthMultiplier
    <
        ui_category = "Depth";
        ui_type = "slider";
        ui_label = "Depth Multiplier";
        ui_min = 0.1; ui_max = 5.0; ui_step = 0.1;
    >
    = 1.0;

    uniform float DepthThreshold
    <
        ui_category = "Depth";
        ui_type = "slider";
        ui_label = "Depth Threshold (Sky)";
        ui_tooltip = "Set the depth threshold to ignore the sky.";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    >
    = 0.50; 

    uniform bool EnableTemporal
    <
        ui_category = "Temporal";
        ui_type = "checkbox";
        ui_label = "Temporal Filtering";
    >
    = false;

    uniform float TemporalFilterStrength
    <
        ui_category = "Temporal";
        ui_type = "slider";
        ui_label = "Temporal Filter Strength";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_tooltip = "Blend factor between current Fog and history.";
    >
    = 0.5;

    uniform float4 FogColor
    <
        ui_category = "General";
        ui_type = "color";
        ui_label = "Fog Color";
        ui_tooltip = "Select the color for the fog.";
    >
    = float4(0.5, 0.5, 0.5, 1.0);

    /*---------------.
    | :: Textures :: |
    '---------------*/

    texture2D FogTex
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    texture2D fogTemporal
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    texture2D fogHistory
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    sampler2D sFog
    {
        Texture = FogTex;
        SRGBTexture = false;
    };

    sampler2D sTemporal
    {
        Texture = fogTemporal;
        SRGBTexture = false;
    };

    sampler2D sFogHistory
    {
        Texture = fogHistory;
        SRGBTexture = false;
    };
    
    /*----------------.
    | :: Functions :: |
    '----------------*/

    // Depth
    float GetLinearDepth(in float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords) * DepthMultiplier;
    }

    // Fog Depth
    float ComputeFogFactor(float depth)
    {
        // Linear fog: 0 at FogStart, 1 at FogEnd.
        float fog = saturate((depth - FogStart) / (FogEnd - FogStart));
        fog *= FogIntensity;
        return saturate(fog);
    }
    
    // Fog
    float4 PS_FogCalc(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float depth = GetLinearDepth(uv);
        float fogFactor = ComputeFogFactor(depth);
        return float4(fogFactor, fogFactor, fogFactor, 1.0);
    }
    
    // Temporal
    float4 PS_Temporal(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float currentFog = tex2D(sFog, uv).r;
        float historyFog = tex2D(sFogHistory, uv).r;
        float fog = EnableTemporal ? lerp(currentFog, historyFog, TemporalFilterStrength) : currentFog;
        return float4(fog, fog, fog, 1.0);
    }
    
    // History
    float4 PS_SaveHistory(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float fog = EnableTemporal ? tex2D(sTemporal, uv).r : tex2D(sFog, uv).r;
        return float4(fog, fog, fog, 1.0);
    }
    
    // Final Image
    float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float4 originalColor = tex2D(ReShade::BackBuffer, uv);
        float fog = EnableTemporal ? tex2D(sTemporal, uv).r : tex2D(sFog, uv).r;
        float depth = GetLinearDepth(uv);

        float4 finalColor;

        switch (ViewMode)
        {
            case 0: // Normal
                finalColor = (depth >= DepthThreshold)
                    ? originalColor
                    : lerp(originalColor, FogColor, fog);
                break;
            case 1: // Fog Debug
                finalColor = float4(fog, fog, fog, 1.0);
                break;
            case 2: // Depth
                finalColor = float4(depth, depth, depth, 1.0);
                break;
            case 3: // Sky Debug
                finalColor = (depth >= DepthThreshold)
                    ? float4(1.0, 0.0, 0.0, 1.0)
                    : float4(depth, depth, depth, 1.0);
                break;
            default:
                finalColor = originalColor;
                break;
        }

        return finalColor;
    }

    /*-------------------.
    | :: Techniques ::   |
    '-------------------*/

    technique NeoFog
    <
        ui_tooltip = "Screen Space Fog";
    >
    {
        pass FogCalc
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_FogCalc;
            RenderTarget = FogTex;
            ClearRenderTargets = true;
        }
        pass Temporal
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Temporal;
            RenderTarget = fogTemporal;
            ClearRenderTargets = true;
        }
        pass SaveHistory
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SaveHistory;
            RenderTarget = fogHistory;
        }
        pass Composite
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Composite;
            SRGBWriteEnable = false;
            BlendEnable = false;
        }
    }
}
