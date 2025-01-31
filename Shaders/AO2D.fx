//+++++++++++++++++++++++++++++++++++++++++++++++++
// 2D Ambient Occlusion
//+++++++++++++++++++++++++++++++++++++++++++++++++
// Author: Barbatos Bachiko
// Version: 0.1
// License: MIT
//+++++++++++++++++++++++++++++++++++++++++++++++++

namespace SSAO2D
{
    #include "ReShade.fxh"

    // Settings
    uniform float AO_Radius <
        ui_type = "slider";
        ui_label = "Occlusion Radius";
        ui_tooltip = "Sampling distance for occlusion calculation";
        ui_min = 1.0;
        ui_max = 50.0;
        ui_step = 1.0;
        ui_default = 7.0;
    > = 7.0;

    uniform float AO_Intensity <
        ui_type = "slider";
        ui_label = "Intensity";
        ui_tooltip = "Strength of the occlusion effect";
        ui_min = 0.0;
        ui_max = 2.0;
        ui_step = 0.01;
        ui_default = 2.0;
    > = 2.0;

    uniform float AO_Power <
        ui_type = "slider";
        ui_label = "Contrast";
        ui_tooltip = "Contrast of the occlusion effect";
        ui_min = 0.5;
        ui_max = 3.0;
        ui_step = 0.01;
        ui_default = 0.5;
    > = 1.8;

    // Textures
    texture2D AOTex
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16;
    };
    texture2D TempTex
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16;
    };

    sampler2D sAOTex
    {
        Texture = AOTex;
    };
    sampler2D sTemp
    {
        Texture = TempTex;
    };

    // Poisson Samples
    static const float2 PoissonSamples[16] =
    {
        float2(-0.94201624, -0.39906216),
        float2(0.94558609, -0.76890725),
        float2(-0.094184101, -0.92938870),
        float2(0.34495938, 0.29387760),
        float2(-0.91588581, 0.45771432),
        float2(-0.81544232, -0.87912464),
        float2(-0.38277543, 0.27676845),
        float2(0.97484398, 0.75648379),
        float2(0.44323325, -0.97511554),
        float2(0.53742981, -0.47373420),
        float2(-0.26496911, -0.41893023),
        float2(0.79197514, 0.19090188),
        float2(-0.24188840, 0.99706507),
        float2(-0.81409955, 0.91437590),
        float2(0.19984126, 0.78641367),
        float2(0.14383161, -0.14100790)
    };

    // Luminance Calculation
    float Luminance(float3 color)
    {
        return dot(color, float3(0.2126, 0.7152, 0.0722));
    }

    float4 AOGen(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        const float3 baseColor = tex2D(ReShade::BackBuffer, uv).rgb;
        const float baseLuminance = Luminance(baseColor);
        
        float occlusion = 0.0;
        const float2 texelSize = 1.0 / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        
        for (int i = 0; i < 16; i++)
        {
            float2 sampleUV = uv + PoissonSamples[i] * AO_Radius * texelSize;
            sampleUV = clamp(sampleUV, 0.0, 1.0);
            
            float3 sampleColor = tex2D(ReShade::BackBuffer, sampleUV).rgb;
            float sampleLuminance = Luminance(sampleColor);
            
            float distanceFactor = 1.0 - length(PoissonSamples[i]);
            occlusion += (baseLuminance - sampleLuminance) * distanceFactor;
        }
        
        occlusion = saturate(occlusion / 16);
        return float4(occlusion, occlusion, occlusion, 1.0);
    }

    static const float weight[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

    float4 BlurHorizontal(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 texelSize = 1.0 / BUFFER_WIDTH;
        float4 result = tex2D(sAOTex, uv) * weight[0];
        
        [unroll]
        for (int i = 1; i < 5; ++i)
        {
            result += tex2D(sAOTex, uv + float2(texelSize.x * i, 0.0)) * weight[i];
            result += tex2D(sAOTex, uv - float2(texelSize.x * i, 0.0)) * weight[i];
        }
        
        return result;
    }

    float4 BlurVertical(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float2 texelSize = 1.0 / BUFFER_HEIGHT;
        float4 result = tex2D(sTemp, uv) * weight[0];
        
        [unroll]
        for (int i = 1; i < 5; ++i)
        {
            result += tex2D(sTemp, uv + float2(0.0, texelSize.y * i)) * weight[i];
            result += tex2D(sTemp, uv - float2(0.0, texelSize.y * i)) * weight[i];
        }
        
        return result;
    }

    float4 Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 color = tex2D(ReShade::BackBuffer, uv).rgb;
        float ao = pow(tex2D(sAOTex, uv).r * AO_Intensity, 1.0 / AO_Power);
        return float4(color * (1.0 - ao), 1.0);
    }

    // Vertex Shader
    void VS(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD)
    {
        uv = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
        pos = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    }

    // Technique
    technique AO2D
    {
        pass AO_Generation
        {
            VertexShader = VS;
            PixelShader = AOGen;
            RenderTarget = AOTex;
        }
        
        pass Horizontal_Blur
        {
            VertexShader = VS;
            PixelShader = BlurHorizontal;
            RenderTarget = TempTex;
        }
        
        pass Vertical_Blur
        {
            VertexShader = VS;
            PixelShader = BlurVertical;
            RenderTarget = AOTex;
        }
        
        pass Composite
        {
            VertexShader = VS;
            PixelShader = Composite;
        }
    }
}
