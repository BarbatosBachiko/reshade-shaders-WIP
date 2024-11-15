/*------------------.
| :: Description :: |
'-------------------/

    Stochastic Screen Space Reflections (SSSR)
    Author: Barbatos Bachiko
    License: MIT

*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform float ReflectionStrength
<
    ui_type = "slider";
    ui_label = "Reflection Strength";
    ui_tooltip = "Controls the intensity of the reflection effect.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
>
= 0.5;

uniform float ReflectionSpread
<
    ui_type = "slider";
    ui_label = "Reflection Spread";
    ui_tooltip = "Controls the spread of reflection samples for SSSR.";
    ui_min = 0.0; ui_max = 0.1; ui_step = 0.001;
>
= 0.003;

uniform int NumSamples
<
    ui_type = "slider";
    ui_label = "Num Samples";
    ui_tooltip = "Number of samples for stochastic reflection. Higher values improve quality.";
    ui_min = 1; ui_max = 64; ui_step = 1;
>
= 16;

uniform bool UseSSSR
<
    ui_label = "Enable SSSR";
    ui_tooltip = "Toggle to enable or disable stochastic screen-space reflections.";
>
= true;

/*---------------.
| :: Textures :: |
'---------------*/

texture2D BackBufferTex : COLOR;
sampler BackBuffer
{
    Texture = BackBufferTex;
};

texture2D NormalMapTex : TEXUNIT0;
sampler NormalMap
{
    Texture = NormalMapTex;
};

/*------------------.
| :: Functions :: |
'------------------*/

// Pseudo-random seed pattern
float Random(float2 seed)
{
    return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
}

// Random function with Halton sequence
float RandomHalton(int sampleIndex, int base = 2)
{
    float result = 0.0;
    float f = 1.0 / base;
    while (sampleIndex > 0)
    {
        result += f * (sampleIndex % base);
        sampleIndex /= base;
        f /= base;
    }
    return result;
}

// Reflection calculation based on normal
float3 CalculateReflection(float3 viewDir, float3 normal, float2 texcoord)
{
    float3 reflectionDir = reflect(viewDir, normal);
    return tex2D(BackBuffer, texcoord + reflectionDir.xy * ReflectionSpread).rgb;
}

// Stochastic SSR
float3 StochasticSSR(float2 texcoord, float3 viewDir, float3 normal)
{
    float3 reflectionColor = float3(0.0, 0.0, 0.0);
    float sampleWeight = 0.0;

    for (int i = 0; i < NumSamples; i++)
    {
        float2 randomOffset = float2(RandomHalton(i), RandomHalton(i + 1)); 
        float3 reflection = CalculateReflection(viewDir, normal, texcoord + randomOffset * ReflectionSpread);
        reflectionColor += reflection * ReflectionStrength;
        sampleWeight += 1.0;
    }

    return reflectionColor / sampleWeight; 
}

// Pixel shader
float3 SSSR_PS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 normal = tex2D(NormalMap, texcoord).xyz * 2.0 - 1.0;
    float3 viewDir = normalize(float3(0.0, 0.0, 1.0) - vpos.xyz);
    float3 baseColor = tex2D(BackBuffer, texcoord).rgb;

    // Apply SSSR if enabled
    if (UseSSSR)
    {
        float3 reflection = StochasticSSR(texcoord, viewDir, normal);
        baseColor = lerp(baseColor, baseColor + reflection, ReflectionStrength);
    }
    
    return saturate(baseColor);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/

technique StochasticSSR
{
    pass P0
    {
        VertexShader = PostProcessVS;
        PixelShader = SSSR_PS;
    }
}