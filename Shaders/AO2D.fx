/*------------------.
| :: Description :: |
'------------------*/

/*
    AO2D
    
    Version 0.2
    Author: Barbatos Bachiko
    License: MIT
    
    About: Ambient Occlusion in 2D.
    
    History:
    (*) Feature (+) Improvement (x) Bugfix (-) Information (!) Compatibility
    
    Version 0.2
    * Configurable sample quality
    * Depth-aware processing option
    * Invert effect toggle
    + Optimized blur pipeline
    * Resolution Scale
*/
namespace A02D
{
#include "ReShade.fxh"

#define INPUT_WIDTH BUFFER_WIDTH
#define INPUT_HEIGHT BUFFER_HEIGHT
#ifndef RES_SCALE
#define RES_SCALE 1.0
#endif
#define RES_WIDTH (INPUT_WIDTH * RES_SCALE)
#define RES_HEIGHT (INPUT_HEIGHT * RES_SCALE)

    /*-------------------.
    | :: Settings ::    |
    '-------------------*/
    
    uniform float AO_Intensity <
        ui_category = "AO";
        ui_type = "slider";
        ui_label = "Intensity";
        ui_min = 0.0;
        ui_max = 4.0;
        ui_step = 0.01;
        ui_default = 1.0;
    > = 2.0;

    uniform float AO_Power <
        ui_category = "AO";
        ui_type = "slider";
        ui_label = "Contrast";
        ui_min = 0.5;
        ui_max = 3.0;
        ui_step = 0.01;
        ui_default = 1.8;
    > = 1.8;
    
    uniform float AO_Radius <
        ui_category = "AO";
        ui_type = "slider";
        ui_label = "Occlusion Radius";
        ui_min = 1.0;
        ui_max = 40.0;
        ui_step = 1.0;
        ui_default = 6.0;
    > = 6.0;

    uniform float AO_Falloff <
        ui_category = "AO";
        ui_type = "slider";
        ui_label = "Sample Falloff";
        ui_min = 0.1;
        ui_max = 5.0;
        ui_step = 0.1;
        ui_default = 1.0;
    > = 1.0;

    uniform int AO_Samples <
        ui_category = "AO";
        ui_type = "slider";
        ui_label = "Sample Quality";
        ui_min = 1;
        ui_max = 8;
        ui_step = 2;
        ui_default = 8;
    > = 8;

    uniform float Blur_Strength <
        ui_category = "Blur";
        ui_type = "slider";
        ui_label = "Blur Strength";
        ui_min = 1.0;
        ui_max = 8.0;
        ui_step = 0.1;
        ui_default = 4.0;
    > = 4.0;
    
    uniform bool AO_UseDepth <
        ui_category = "Extra"; 
        ui_label = "Use Depth";
        ui_tooltip = "if available";
        ui_default = false;
    > = false;

    uniform bool AO_InvertEffect <
        ui_category = "Extra";
        ui_label = "Invert Effect";
        ui_default = false;
    > = false;

    /*---------------.
    | :: Textures :: |
    '---------------*/
    
    texture2D AOTex
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = R16F;
    };
    texture2D TempTex
    {
        Width = RES_WIDTH;
        Height = RES_HEIGHT;
        Format = R16F;
    };

    sampler2D sAOTex
    {
        Texture = AOTex;
    };
    sampler2D sTemp
    {
        Texture = TempTex;
    };

    /*----------------.
    | :: Functions :: |
    '----------------*/
    
    // Poisson Samples
    static const float2 PoissonSamples[8] =
    {
        float2(-0.94201624, -0.39906216),
        float2(0.94558609, -0.76890725),
        float2(-0.094184101, -0.92938870),
        float2(0.34495938, 0.29387760),
        float2(-0.81544232, -0.87912464),
        float2(0.53742981, -0.47373420),
        float2(-0.26496911, -0.41893023),
        float2(0.79197514, 0.19090188),
    };

    float Luminance(float3 color)
    {
        return dot(color, float3(0.2126, 0.7152, 0.0722));
    }

    float GetLinearDepth(float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords);
    }

    float4 AOGen(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        const float3 baseColor = tex2D(ReShade::BackBuffer, uv).rgb;
        const float baseLuminance = Luminance(baseColor);
        float baseDepth = AO_UseDepth ? GetLinearDepth(uv) : 0.0;
        
        float occlusion = 0.0;
        const float2 texelSize = 1.0 / float2(RES_WIDTH, RES_HEIGHT);
        
        for (int i = 0; i < AO_Samples; ++i)
        {
            float2 sampleUV = uv + PoissonSamples[i] * AO_Radius * texelSize;
            sampleUV = saturate(sampleUV);
            
            float3 sampleColor = tex2Dlod(ReShade::BackBuffer, float4(sampleUV, 0, 0)).rgb;
            float sampleLuminance = Luminance(sampleColor);
            
            float distanceFactor = 1.0 - saturate(length(PoissonSamples[i]) * AO_Falloff);
            
            if (AO_UseDepth)
            {
                float sampleDepth = GetLinearDepth(sampleUV);
                distanceFactor *= 1.0 - saturate(abs(baseDepth - sampleDepth) * 10.0);
            }
            
            occlusion += (baseLuminance - sampleLuminance) * distanceFactor;
        }
        
        occlusion = saturate(occlusion / AO_Samples);
        return occlusion.rrrr;
    }

    void GetBlurWeights(out float weights[3])
    {
        float sigma = Blur_Strength * 0.5;
        weights[0] = exp(-0.0 / (2.0 * sigma * sigma));
        weights[1] = exp(-1.0 / (2.0 * sigma * sigma));
        weights[2] = exp(-4.0 / (2.0 * sigma * sigma));
        
        float total = weights[0] + 2.0 * (weights[1] + weights[2]);
        weights[0] /= total;
        weights[1] /= total;
        weights[2] /= total;
    }

    float4 BlurHorizontal(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float weights[3];
        GetBlurWeights(weights);
        
        float2 texelSize = 1.0 / RES_WIDTH;
        float4 result = tex2D(sAOTex, uv) * weights[0];
        
        [unroll]
        for (int i = 1; i < 3; ++i)
        {
            result += tex2D(sAOTex, uv + float2(texelSize.x * i, 0.0)) * weights[i];
            result += tex2D(sAOTex, uv - float2(texelSize.x * i, 0.0)) * weights[i];
        }
        
        return result;
    }

    float4 BlurVertical(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float weights[3];
        GetBlurWeights(weights);
        
        float2 texelSize = 1.0 / RES_HEIGHT;
        float4 result = tex2D(sTemp, uv) * weights[0];
        
        for (int i = 1; i < 3; ++i)
        {
            result += tex2D(sTemp, uv + float2(0.0, texelSize.y * i)) * weights[i];
            result += tex2D(sTemp, uv - float2(0.0, texelSize.y * i)) * weights[i];
        }
        
        return result;
    }

    float4 Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 color = tex2D(ReShade::BackBuffer, uv).rgb;
        float ao = pow(tex2D(sAOTex, uv).r * AO_Intensity, 1.0 / AO_Power);
        
        if (AO_InvertEffect)
            return float4(color * (1.0 + ao), 1.0);
        else
            return float4(color * (1.0 - ao), 1.0);
    }

    /*-------------------.
    | :: Techniques ::   |
    '-------------------*/
    
    technique AO2D
    {
        pass AO_Gen
        {
            VertexShader = PostProcessVS;
            PixelShader = AOGen;
            RenderTarget = AOTex;
        }
        
        pass Horizontal_Blur
        {
            VertexShader = PostProcessVS;
            PixelShader = BlurHorizontal;
            RenderTarget = TempTex;
        }
        
        pass Vertical_Blur
        {
            VertexShader = PostProcessVS;
            PixelShader = BlurVertical;
            RenderTarget = AOTex;
        }
        
        pass Composite
        {
            VertexShader = PostProcessVS;
            PixelShader = Composite;
        }
    }
}
