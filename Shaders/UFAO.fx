/*-------------------------------------------------|
| ::                 uFakeHDR                   :: |
'--------------------------------------------------|
| Version: 2.1                                     |
| Author: Barbatos                                 |
| License: CC0                                     |
'---------------------------------------------------*/

#include "ReShade.fxh"

//----------------|
// :: Textures :: |
//----------------|

texture TexLumBlur { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA8; };
sampler SamplerLumBlur { Texture = TexLumBlur; };

//----------|
// :: UI :: |
//----------|

uniform float HDRPower <
    ui_type = "slider";
    ui_label = "HDR Power";
    ui_min = 0.1; ui_max = 4.0;
> = 2.0;

uniform float LocalContrastStrength <
    ui_type = "slider";
    ui_label = "Local Contrast";
    ui_min = 0.0; ui_max = 2.0;
> = 0.3; 

uniform float Saturation <
    ui_type = "slider";
    ui_label = "Saturation";
    ui_tooltip = "Adjust the color saturation.";
    ui_min = 0.0; ui_max = 2.0;
> = 1.0;

uniform int HDRExtraMode <
    ui_type = "combo";
    ui_label = "Extra Mode";
    ui_items = "None\0Multiple Exposures\0";
> = 1;

//--------------------|
// :: Pixel Shaders ::|
//--------------------|

float4 PS_Blur(float4 pos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    float3 col = tex2D(ReShade::BackBuffer, uv).rgb;
    
    float2 pixelSize = ReShade::PixelSize * 2.0;
    
    col += tex2D(ReShade::BackBuffer, uv + float2( pixelSize.x,  0.0)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2(-pixelSize.x,  0.0)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2( 0.0,  pixelSize.y)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2( 0.0, -pixelSize.y)).rgb;
    
    col += tex2D(ReShade::BackBuffer, uv + float2( pixelSize.x,  pixelSize.y)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2(-pixelSize.x, -pixelSize.y)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2( pixelSize.x, -pixelSize.y)).rgb;
    col += tex2D(ReShade::BackBuffer, uv + float2(-pixelSize.x,  pixelSize.y)).rgb;

    return float4(col / 9.0, 1.0);
}

float4 FHDR(float4 pos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    float3 color = tex2D(ReShade::BackBuffer, uv).rgb;
    
    if (LocalContrastStrength > 0.0)
    {
        float3 blurred = tex2D(SamplerLumBlur, uv).rgb;
        
        const float3 lumaCoeff = float3(0.2126, 0.7152, 0.0722);
        float lumaOrig = dot(color, lumaCoeff);
        float lumaBlur = dot(blurred, lumaCoeff);
        
        float localDiff = lumaOrig - lumaBlur;
        
        color += localDiff * LocalContrastStrength;
        color = saturate(color);
    }

    float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
    float sceneLum = lum * 0.5;

    float3 c = pow(color, HDRPower);

    float adjust = lerp(1.0, clamp(0.5 / (sceneLum + 0.001), 0.5, 2.0), 0.5);
    c = saturate(c * adjust);

    if (HDRExtraMode == 1)
    {
        c = sqrt(c);
    }
    
    float gray = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = lerp(gray, c, Saturation);
    return float4(saturate(c), 1.0);
}

technique UFakeHDR
<
    ui_label = "uFakeHDR";
    ui_tooltip = "Make the game less gray ;)";
>
{
    pass BlurPass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_Blur;
        RenderTarget = TexLumBlur;
    }

    pass MainPass
    {
        VertexShader = PostProcessVS;
        PixelShader = FHDR;
    }
}
