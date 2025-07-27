/*
    Cinematic Bleach
    Version 1.0
    Author: Barbados Bachiko 
    License: MIT
*/

#include "ReShade.fxh"

uniform float Strength <
    ui_category = "Bleach Bypass Settings";
    ui_type = "slider";
    ui_label = "Strength";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 1.0;

uniform float Contrast <
    ui_category = "Bleach Bypass Settings";
    ui_type = "slider";
    ui_label = "Contrast";
    ui_min = 1.0;
    ui_max = 5.0;
    ui_step = 0.05;
> = 2.5;

uniform float Desaturation <
    ui_category = "Bleach Bypass Settings";
    ui_type = "slider";
    ui_label = "Desaturation";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.6;

uniform float GrainIntensity <
    ui_category = "Film Grain";
    ui_type = "slider";
    ui_label = "Grain Intensity";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.08;

uniform float timer < source = "timer"; >;

static const float3 LumaCoeff = float3(0.2126, 0.7152, 0.0722);

float GetLuminance(float3 color)
{
    return dot(color, LumaCoeff);
}

float random(float2 uv)
{
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453123 + (timer * 0.001));
}

float4 BleachBypassPass(float4 pos : SV_Position, float2 uv : TexCoord) : SV_Target
{
    float3 originalColor = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 color = originalColor;

    color = pow(abs(color), Contrast);
    
    float lum = GetLuminance(color);
    float3 gray = float3(lum, lum, lum);
    
    color = lerp(color, gray, Desaturation);
    
    float grain = (random(uv) * 2.0 - 1.0) * GrainIntensity;
    color += grain;
    
    color = lerp(originalColor, color, Strength);
    
    return float4(saturate(color), 1.0);
}

technique CinematicBleach
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = BleachBypassPass;
    }
}