/*------------------.
| :: Description :: |
'-------------------/

    Ultra Fast Ambient Occlusion (UFAO)

    Version 1.3
    Author: Barbatos Bachiko
    License: MIT

    About: the only goal is to get maximum performance with ambient occlusion.
    History:
    (*) Feature (+) Improvement	(x) Bugfix (-) Information (!) Compatibility

    Version 1.3
    + Add Blur filter

*/

namespace UFAO
{
#ifndef RENDER_SCALE
#define RENDER_SCALE 1.0
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

    uniform float BLURING_AMOUNT <
	ui_type = "drag";
	ui_min = 0.0; ui_max = 8.0;
    ui_step = 0.1;
    ui_label = "Bluring amount";
	ui_tooltip = "Less noise but less details";
    ui_category = "Filtering";
> = 1.0;
    
    
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
    
    texture2D NormalTex
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };
    
    texture fBlurTexture0
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };
    sampler blurTexture0
    {
        Texture = fBlurTexture0;
    };
    
    texture fBlurTexture1
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };
    sampler blurTexture1
    {
        Texture = fBlurTexture1;
    };

    texture fBlurTexture2
    {
        Width = BUFFER_WIDTH;
        Height = BUFFER_HEIGHT;
        Format = RGBA16F;
    };
    sampler blurTexture2
    {
        Texture = fBlurTexture2;
    };

    /*----------------.
    | :: Funções ::  |
    '----------------*/

    float GetLinearDepth(float2 coords)
    {
        return ReShade::GetLinearizedDepth(coords) * fDepthMultiplier;
    }
    
    float3 GetNormalFromDepth(float2 texcoord)
    {
        float3 offset = float3(BUFFER_PIXEL_SIZE, 0.0);
        float2 posCenter = texcoord.xy;
        float2 posNorth = posCenter - offset.zy;
        float2 posEast = posCenter + offset.xz;

        float3 vertCenter = float3(posCenter - 0.5, 1.0) * GetLinearDepth(posCenter);
        float3 vertNorth = float3(posNorth - 0.5, 1.0) * GetLinearDepth(posNorth);
        float3 vertEast = float3(posEast - 0.5, 1.0) * GetLinearDepth(posEast);

        return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)) * 0.5 + 0.5;
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

    float SAO(float2 texcoord)
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
        float ao = SAO(origTexcoord);
        return float4(ao, ao, ao, 1.0);
    }
    
    float4 PS_Normals(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float3 normal = GetNormalFromDepth(uv);
        return float4(normal, 1.0);
    }

    float4 Composite_PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
    {
        float4 originalColor = tex2D(ReShade::BackBuffer, uv);
        float ao = tex2D(blurTexture2, uv * RENDER_SCALE).r;
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

    // Downsampling Function - Phase 0
    float4 Downsample0(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float2 pixelSize = ReShade::PixelSize * BLURING_AMOUNT;
        float4 color = tex2D(sAO, texcoord + float2(-pixelSize.x, -pixelSize.y));
        color += tex2D(sAO, texcoord + float2(pixelSize.x, -pixelSize.y));
        color += tex2D(sAO, texcoord + float2(-pixelSize.x, pixelSize.y));
        color += tex2D(sAO, texcoord + float2(pixelSize.x, pixelSize.y));
        color *= 0.25;
        return color;
    }

// Downsampling Function - Phase 1
    float4 Downsample1(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float2 pixelSize = ReShade::PixelSize * 2 * BLURING_AMOUNT;
        float4 color = tex2D(blurTexture0, texcoord + float2(-pixelSize.x, -pixelSize.y));
        color += tex2D(blurTexture0, texcoord + float2(pixelSize.x, -pixelSize.y));
        color += tex2D(blurTexture0, texcoord + float2(-pixelSize.x, pixelSize.y));
        color += tex2D(blurTexture0, texcoord + float2(pixelSize.x, pixelSize.y));
        color *= 0.25;
        return color;
    }

// Downsampling Function - Phase 2
    float4 Downsample2(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
    {
        float2 pixelSize = ReShade::PixelSize * 4 * BLURING_AMOUNT;
        float4 color = tex2D(blurTexture1, texcoord + float2(-pixelSize.x, -pixelSize.y));
        color += tex2D(blurTexture1, texcoord + float2(pixelSize.x, -pixelSize.y));
        color += tex2D(blurTexture1, texcoord + float2(-pixelSize.x, pixelSize.y));
        color += tex2D(blurTexture1, texcoord + float2(pixelSize.x, pixelSize.y));
        color *= 0.25;
        return color;
    }
    
    /*-----------------.
    | :: Técnicas ::  |
    '-----------------*/

    technique UFAO
    {
        pass Normal
        {
            VertexShader = PostProcessVS;
            PixelShader = PS_Normals;
            RenderTarget = NormalTex;
        }
        pass AOPass
        {
            VertexShader = PostProcessVS;
            PixelShader = AO_PS;
            RenderTarget = AOTex;
        }
        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = Downsample0;
            RenderTarget0 = fBlurTexture0;
        }

        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = Downsample1;
            RenderTarget0 = fBlurTexture1;
        }

        pass
        {
            VertexShader = PostProcessVS;
            PixelShader = Downsample2;
            RenderTarget0 = fBlurTexture2;
        }
        pass Composite
        {
            VertexShader = PostProcessVS;
            PixelShader = Composite_PS;
        }
    }
}
