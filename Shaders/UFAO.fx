/*------------------.
| :: Description :: |
'-------------------/

 Ultra Fast Ambient Occlusion (UFAO) 

    Version 1.0 (Remake)
    Author: Barbatos Bachiko
    License: MIT
    
    About: the only goal is to get maximum performance with ambient occlusion.
    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

    Version 1.0
    * Temporal Filtering
    * Brightness Threshold and Fade
    * Adjustable Sample Count, Radius and Angle Mode
    * NeoSSAO AO Algorithm
*/

namespace UFAO
{
    #define INPUT_WIDTH BUFFER_WIDTH 
    #define INPUT_HEIGHT BUFFER_HEIGHT 

    #ifndef RES_SCALE
    #define RES_SCALE 0.7
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
        ui_tooltip = "Select the view mode for AO";
        ui_items = "Normal\0AO Debug\0Depth\0Sky Debug\0Normal Debug\0";
    >
    = 0;

    uniform int SampleCount
    <
        ui_category = "General";
        ui_type = "slider";
        ui_label = "Sample Count";
        ui_min = 1.0; ui_max = 4.0; ui_step = 1.0;
    >
    = 4;

    uniform float Intensity
    <
        ui_category = "General";
        ui_type = "slider";
        ui_label = "AO Intensity";
        ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    >
    = 0.7;

    uniform float SampleRadius
    <
        ui_category = "General";
        ui_type = "slider";
        ui_label = "Sample Radius";
        ui_min = 0.001; ui_max = 10.0; ui_step = 0.001;
    >
    = 5.0;

    uniform int AngleMode
    <
        ui_category = "AO Kernel";
        ui_type = "combo";
        ui_label = "Angle Mode";
        ui_items = "Horizon Only\0Vertical Only\0Unilateral\0Bidirectional\0";
    >
    = 3;

    uniform float FadeStart
    <
        ui_category = "Fade";
        ui_type = "slider";
        ui_label = "Fade Start";
        ui_tooltip = "Distance at which AO starts to fade out";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 0.0;

    uniform float FadeEnd
    <
        ui_category = "Fade";
        ui_type = "slider";
        ui_label = "Fade End";
        ui_tooltip = "Distance at which AO completely fades out";
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
    = 0.5;

    uniform float DepthSmoothEpsilon
    <
        ui_category = "Depth";
        ui_type = "slider";
        ui_label = "Depth Smooth Epsilon";
        ui_tooltip = "Controls the smoothing of depth comparison";
        ui_min = 0.0001; ui_max = 0.01; ui_step = 0.0001;
    >
    = 0.0005;
    
    uniform float DepthThreshold
    <
        ui_category = "Depth";
        ui_type = "slider";
        ui_label = "Depth Threshold (Sky)";
        ui_tooltip = "Set the depth threshold to ignore the sky";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    >
    = 0.50; 
    
    uniform bool EnableTemporal
    <
        ui_category = "Temporal";
        ui_type = "checkbox";
        ui_label = "Temporal Filtering";
    >
    = true;

    uniform float TemporalFilterStrength
    <
        ui_category = "Temporal";
        ui_type = "slider";
        ui_label = "Temporal Filter";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
        ui_tooltip = "Blend factor between current AO and history";
    >
    = 0.25;

    uniform bool EnableBrightnessThreshold
    < 
        ui_category = "Extra";
        ui_type = "checkbox";
        ui_label = "Enable Brightness Threshold"; 
        ui_tooltip = "Enable or disable the brightness threshold";
    > 
    = false;

    uniform float BrightnessThreshold
    <
        ui_category = "Extra";
        ui_type = "slider";
        ui_label = "Brightness Threshold";
        ui_tooltip = "Pixels with brightness above this threshold will have reduced occlusion";
        ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    >
    = 0.8; 
    
    uniform float4 OcclusionColor
    <
        ui_category = "Extra";
        ui_type = "color";
        ui_label = "Occlusion Color";
        ui_tooltip = "Color for ambient occlusion";
    >
    = float4(0.0, 0.0, 0.0, 1.0);
    

    /*---------------.
    | :: Textures :: |
    '---------------*/
    texture2D AOTex
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    texture2D ufaoTemporal
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    texture2D ufaoHistory
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = RGBA8;
    };

    sampler2D sAO
    {
        Texture = AOTex;
        SRGBTexture = false;
    };

    sampler2D sTemporal
    {
        Texture = ufaoTemporal;
        SRGBTexture = false;
    };

    sampler2D sAOHistory
    {
        Texture = ufaoHistory;
        SRGBTexture = false;
    };
    
    /*----------------.
    | :: Functions :: |
    '----------------*/

    float GetLinearDepth(in float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords) * DepthMultiplier;
    }

    float3 GetScreenSpaceNormal(in float2 texcoord)
    {
        float3 offset = float3(BUFFER_PIXEL_SIZE, 0.0);
        float2 posCenter = texcoord;
        float2 posNorth = posCenter - offset.zy;
        float2 posEast = posCenter + offset.xz;

        float depthCenter = GetLinearDepth(posCenter);
        float depthNorth = GetLinearDepth(posNorth);
        float depthEast = GetLinearDepth(posEast);

        float3 vertCenter = float3(posCenter - 0.5, 1) * depthCenter;
        float3 vertNorth = float3(posNorth - 0.5, 1) * depthNorth;
        float3 vertEast = float3(posEast - 0.5, 1) * depthEast;

        return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)) * 0.5 + 0.5;
    }
    
    float CalculateBrightness(float3 color)
    {
        return dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    }
    
    float PS_UFAO_Main(in float2 uv)
    {
        float currentDepth = GetLinearDepth(uv);
        float occlusion = 0.0;
        
        // Gets the original color to apply the brightness threshold to
        float3 originalColor = tex2D(ReShade::BackBuffer, uv).rgb;
        float brightness = CalculateBrightness(originalColor);
        float brightnessFactor = EnableBrightnessThreshold ? saturate(1.0 - smoothstep(BrightnessThreshold - 0.1, BrightnessThreshold + 0.1, brightness)) : 1.0;
        
        // Loop
        for (int i = 0; i < SampleCount; i++)
        {
            float angle = 0.0;
            if (AngleMode == 3) // Bidirectional: full circle sampling
            {
                angle = (i + 0.5) * 6.28318530718 / SampleCount;
            }
            else if (AngleMode == 0) // Horizon Only: samples in opposite directions horizontally
            {
                angle = (i % 2 == 0) ? 0.0 : 3.14159265359;
            }
            else if (AngleMode == 1) // Vertical Only: samples up and down
            {
                angle = (i % 2 == 0) ? 1.570796327 : 4.71238898;
            }
            else // Unilateral: sample in semicircle
            {
                angle = (i + 0.5) * 3.14159265359 / SampleCount;
            }
            float2 offset = float2(cos(angle), sin(angle)) * SampleRadius * ReShade::PixelSize.x;
            float neighborDepth = GetLinearDepth(uv + offset);
            float depthDiff = currentDepth - neighborDepth;
            float hit = saturate(depthDiff * (1.0 / (DepthSmoothEpsilon + 1e-6)));
            occlusion += hit;
        }
        occlusion = (occlusion / SampleCount) * Intensity;
        occlusion *= brightnessFactor;
        
        // Fade
        float fade = (currentDepth < FadeStart) ? 1.0 : saturate((FadeEnd - currentDepth) / (FadeEnd - FadeStart));
        occlusion *= fade;
        
        return occlusion;
    }
    
    float4 PS_UFAO(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float ao = PS_UFAO_Main(uv);
        return float4(ao, ao, ao, 1.0);
    }
    
    float4 PS_Temporal(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float currentAO = tex2D(sAO, uv).r;
        float historyAO = tex2D(sAOHistory, uv).r;
        float ao = EnableTemporal ? lerp(currentAO, historyAO, TemporalFilterStrength) : currentAO;
        return float4(ao, ao, ao, 1.0);
    }

    float4 PS_SaveHistory(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float ao = EnableTemporal ? tex2D(sTemporal, uv).r : tex2D(sAO, uv).r;
        return float4(ao, ao, ao, 1.0);
    }
    
    float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float4 originalColor = tex2D(ReShade::BackBuffer, uv);
        float ao = EnableTemporal ? tex2D(sTemporal, uv).r : tex2D(sAO, uv).r;
        float currentDepth = GetLinearDepth(uv);
        float3 normal = GetScreenSpaceNormal(uv);

        switch (ViewMode)
        {
            case 0: // Normal
                return (currentDepth >= DepthThreshold)
                    ? originalColor
                    : originalColor * (1.0 - saturate(ao)) + OcclusionColor * saturate(ao);
            case 1: // AO Debug
                return float4(1.0 - ao, 1.0 - ao, 1.0 - ao, 1.0);
            case 2: // Depth
                return float4(currentDepth, currentDepth, currentDepth, 1.0);
            case 3: // Sky Debug
                return (currentDepth >= DepthThreshold)
                    ? float4(1.0, 0.0, 0.0, 1.0)
                    : float4(currentDepth, currentDepth, currentDepth, 1.0);
            case 4: // Normal Debug
                return float4(normal * 0.5 + 0.5, 1.0);
        }
        return originalColor;
    }

    /*-------------------.
    | :: Techniques ::   |
    '-------------------*/
    technique UltraFastAO
    {
        pass AO
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_UFAO;
            RenderTarget = AOTex;
            ClearRenderTargets = true;
        }
        pass Temporal
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Temporal;
            RenderTarget = ufaoTemporal;
            ClearRenderTargets = true;
        }
        pass SaveHistory
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_SaveHistory;
            RenderTarget = ufaoHistory;
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
