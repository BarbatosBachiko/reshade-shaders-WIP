/*------------------.
| :: Description :: |
'-------------------/

	MLAA (Version: 0.2)
	
	Author: BarbatosBachiko
	About: Applies anti-aliasing using machine learning 

	Changelog:
	* Removed FXAA integration.
	* Added debug mode for edge detection visualization.

*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

// Adjustable settings
uniform float EdgeThreshold
< 
	__UNIFORM_SLIDER_FLOAT1 
	ui_min = 0.0; 
	ui_max = 1.0; 
	ui_label = "Edge Detection Threshold"; 
	ui_tooltip = "The minimum local contrast required to classify an edge.";
> = 0.125;

uniform bool DebugEdges
< 
	ui_label = "Debug Edges";
	ui_tooltip = "Visualize edge detection for debugging."; 
> = false;

/*---------------.
| :: Textures :: |
'---------------*/

texture MLWeights
{
    Width = 128;
    Height = 128;
    Format = RGBA32F;
};
texture BackBufferTex : COLOR;

/*---------------.
| :: Samplers :: |
'---------------*/

sampler BackBuffer
{
    Texture = BackBufferTex;
    MinFilter = Linear;
    MagFilter = Linear;
};
sampler WeightSampler
{
    Texture = MLWeights;
    MinFilter = Linear;
    MagFilter = Linear;
};

/*----------------.
| :: Functions :: |
'----------------*/

// MLAA Function (Machine Learning Anti-Aliasing)
float4 MLAA(float2 texcoord)
{
    float4 color = tex2D(BackBuffer, texcoord);
    float4 weights = tex2D(WeightSampler, texcoord);
    float4 antiAliasedColor = lerp(color, (color + weights), 0.5); 
    
    return antiAliasedColor;
}

// Edge Detection Visualization
float EdgeDetection(float2 texcoord, float2 rcpFrame)
{
    float3 rgbNW = tex2D(BackBuffer, texcoord + float2(-rcpFrame.x, -rcpFrame.y)).rgb;
    float3 rgbNE = tex2D(BackBuffer, texcoord + float2(rcpFrame.x, -rcpFrame.y)).rgb;
    float3 rgbSW = tex2D(BackBuffer, texcoord + float2(-rcpFrame.x, rcpFrame.y)).rgb;
    float3 rgbSE = tex2D(BackBuffer, texcoord + float2(rcpFrame.x, rcpFrame.y)).rgb;
    float3 rgbM = tex2D(BackBuffer, texcoord).rgb;

    float lumaNW = dot(rgbNW, float3(0.299, 0.587, 0.114));
    float lumaNE = dot(rgbNE, float3(0.299, 0.587, 0.114));
    float lumaSW = dot(rgbSW, float3(0.299, 0.587, 0.114));
    float lumaSE = dot(rgbSE, float3(0.299, 0.587, 0.114));
    float lumaM = dot(rgbM, float3(0.299, 0.587, 0.114));

    float edgeHorizontal = abs(lumaNW + lumaNE - lumaSW - lumaSE);
    float edgeVertical = abs(lumaNW + lumaSW - lumaNE - lumaSE);
    float edgeStrength = max(edgeHorizontal, edgeVertical);

    return (edgeStrength >= EdgeThreshold) ? edgeStrength : 0.0;
}

// Main pixel shader function
float4 AAPixelShader(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    if (DebugEdges)
    {
        float edgeStrength = EdgeDetection(texcoord, float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT));
        return float4(edgeStrength, edgeStrength, edgeStrength, 1.0);
    }
    else
    {
        return MLAA(texcoord);
    }
}

// Vertex Shader
void CustomPostProcessVS(in uint id : SV_VertexID, out float4 vpos : SV_Position, out float2 texcoord : TEXCOORD)
{
    texcoord = float2((id == 2) ? 2.0 : 0.0, (id == 1) ? 2.0 : 0.0);
    vpos = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/

technique MLAA
{
    pass
    {
        VertexShader = CustomPostProcessVS;
        PixelShader = AAPixelShader;
    }
}
