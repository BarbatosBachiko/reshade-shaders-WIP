/*------------------.
| :: Description :: |
'-------------------/

    Temporal Anti-Aliasing (version 0.1)

    Author: Barbatos Bachiko
    License: MIT

    About:
    This shader implements the Temporal Anti-Aliasing

    Ideas for future improvement:
    * Performance optimization 
    
    History:
    (*) Feature (+) Improvement (x) Bugfix (-) Information (!) Compatibility

*/

/*---------------.
| :: Includes :: |
'---------------*/

#include "ReShade.fxh"
#include "ReShadeUI.fxh"

/*---------------.
| :: Settings :: |
'---------------*/

uniform int View_Mode
<
    ui_type = "combo";
    ui_label = "View Mode";
    ui_tooltip = "Select view mode.";
    ui_items = "Normal\0Complexity Mask\0Edge Mask\0";
>
= 0;

uniform float alpha
<
    ui_type = "slider";
    ui_label = "Smoothing Factor (α)";
    ui_tooltip = "Adjust the smoothing factor for the EMA.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
>
= 0.1;

uniform float view_width
<
    ui_type = "slider";
    ui_label = "Screen Width";
    ui_tooltip = "Adjust to screen width.";
    ui_min = 800.0; ui_max = 3840.0; ui_step = 1.0;
>
= 1920.0;

uniform float view_height
<
    ui_type = "slider";
    ui_label = "Screen Height";
    ui_tooltip = "Adjust the height of the screen.";
    ui_min = 600.0; ui_max = 2160.0; ui_step = 1.0;
>
= 1080.0;

uniform float complexity_threshold
<
    ui_type = "slider";
    ui_label = "Complexity Threshold";
    ui_tooltip = "Sets the threshold for determining visual complexity.";
    ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
>
= 0.5;

/*---------------.
| :: Textures :: |
'---------------*/

texture2D BackBufferTex : COLOR;
texture2D HistoryTex : COLOR; 
texture2D VelocityTex : RG16; 
sampler BackBuffer
{
    Texture = BackBufferTex;
};
sampler History
{
    Texture = HistoryTex;
};
sampler Velocity
{
    Texture = VelocityTex;
};

texture2D SegmentHistoryTex : COLOR; 
sampler SegmentHistory
{
    Texture = SegmentHistoryTex;
};

texture2D DepthTex : DEPTH; 
sampler DepthSampler
{
    Texture = DepthTex;
};

/*----------------.
| :: Functions :: |
'----------------*/

// Function to calculate the Halton sequence
float HaltonSequence(int index, int base)
{
    // Ensure the index is non-negative and base is greater than 1
    if (index < 0 || base <= 1)
    {
        return 0.0; // Return 0 for invalid inputs
    }

    float result = 0.0;
    float fraction = 1.0 / base;

    // Calculate the Halton sequence value
    while (index > 0)
    {
        result += (index % base) * fraction;
        index /= base;
        fraction /= base; // Update fraction for the next digit
    }

    return result;
}

// Function to calculate velocity dilation
float2 DilateVelocity(float2 texcoord)
{
    float2 velocities[9];
    float2 offsets[9] =
    {
        float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-1, 0), float2(0, 0), float2(1, 0),
        float2(-1, 1), float2(0, 1), float2(1, 1)
    };

    // Sample velocities from surrounding pixels
    for (int i = 0; i < 9; ++i)
    {
        velocities[i] = tex2D(Velocity, texcoord + offsets[i] / float2(view_width, view_height)).rg;
    }

    // Initialize max_velocity with the center pixel velocity
    float2 max_velocity = velocities[4];

    // Find the maximum velocity among the sampled velocities
    for (int i = 0; i < 9; ++i)
    {
        if (length(velocities[i]) > length(max_velocity))
        {
            max_velocity = velocities[i];
        }
    }

    return max_velocity;
}

// Function to calculate the average of the minimum and maximum values of the neighbors
float3 ShapedNeighborhoodClamp(float2 texcoord)
{
    float3 neighbors[9];
    float2 offsets[9] =
    {
        float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-1, 0), float2(0, 0), float2(1, 0),
        float2(-1, 1), float2(0, 1), float2(1, 1)
    };

    // Collect colors from neighboring pixels
    for (int i = 0; i < 9; ++i)
    {
        neighbors[i] = tex2D(BackBuffer, texcoord + offsets[i] / float2(view_width, view_height)).rgb;
    }

    // Calculate minimums and maximums for the top and bottom rows of neighbors
    float3 min_top = min(neighbors[0], min(neighbors[1], neighbors[2]));
    float3 max_top = max(neighbors[0], max(neighbors[1], neighbors[2]));
    float3 min_bottom = min(neighbors[6], min(neighbors[7], neighbors[8]));
    float3 max_bottom = max(neighbors[6], max(neighbors[7], neighbors[8]));

    // Calculate the average of minimum and maximum values
    float3 min_average = (min_top + min_bottom) * 0.5;
    float3 max_average = (max_top + max_bottom) * 0.5;

    // Perform rounded neighborhood clamp using dilated velocity
    return clamp(tex2D(History, texcoord + DilateVelocity(texcoord)).rgb, min_average, max_average);
}

// Calculate the Exponential Moving Average (EMA) color
float3 CalculateEMAColor(float2 texcoord, float2 velocity)
{
    // Displace the texture coordinate based on the velocity
    float2 displaced_texcoord = texcoord + velocity;

    // Sample the current color and the history color using shaped neighborhood clamp
    float3 current_color = tex2D(BackBuffer, texcoord).rgb;
    float3 history_color = ShapedNeighborhoodClamp(displaced_texcoord);

    // Calculate the EMA color by blending current and historical colors
    return (1.0 - alpha) * current_color + alpha * history_color;
}

// Function to update the Segmentation History
float4 UpdateSegmentHistory(float2 texcoord)
{
    // Sample the current segment color from the back buffer
    float4 current_segment = tex2D(BackBuffer, texcoord);
    
    // Sample the previous segmentation history
    float4 segment_history = tex2D(SegmentHistory, texcoord);

    // Define a threshold for alpha to determine if the pixel is part of the ATAA
    const float alphaThreshold = 0.5;

    // Check if the current pixel is significant (e.g., has sufficient alpha)
    bool isSignificantPixel = (current_segment.a > alphaThreshold);
    
    float brightnessThreshold = 0.3; // Example threshold for brightness
    bool isBrightPixel = (current_segment.r + current_segment.g + current_segment.b) / 3.0 > brightnessThreshold;

    // Combine conditions to mark the pixel
    if (isSignificantPixel || isBrightPixel)
    {
        // Blend the current segment with the previous history for smoother transitions
        float blendFactor = 0.5; // Adjust this factor as needed for blending
        return lerp(segment_history, float4(1.0, 1.0, 1.0, 1.0), blendFactor); // Mark and blend with white
    }
    else
    {
        return segment_history; // Keep previous history if pixel is not marked
    }
}

// Function to calculate luminance from a color
float CalculateLuminance(float3 color)
{
    // Ensure the color values are clamped between 0 and 1
    color = saturate(color); // Clamps the values to [0, 1]

    // Define luminance coefficients for RGB channels
    const float3 luminanceCoefficients = float3(0.299, 0.587, 0.114);

    // Calculate and return the luminance using the dot product
    return dot(color, luminanceCoefficients);
}

// Function to calculate temporal luminance change
float TemporalLuminanceChange(float2 texcoord)
{
    // Sample the current and previous colors from the back buffer and history
    float3 currentColor = tex2D(BackBuffer, texcoord).rgb;
    float3 previousColor = tex2D(History, texcoord).rgb;

    // Calculate luminance for the current and previous frames
    float current_luminance = CalculateLuminance(currentColor);
    float previous_luminance = CalculateLuminance(previousColor);

    // Calculate the absolute change in luminance
    float luminance_change = abs(current_luminance - previous_luminance);

    // Optional: Scale the change to avoid excessive darkening
    const float scaleFactor = 2.0; // Adjust this factor based on desired sensitivity
    float adjustedChange = luminance_change * scaleFactor;

    // Clamp the result to avoid negative values or excessive brightness
    return saturate(adjustedChange);
}

// Function to calculate the luminance change in a neighborhood of pixels
float NeighborhoodLuminanceChange(float2 texcoord)
{
    // Array to store luminance changes from neighboring pixels
    float luminance_changes[9];
    
    // Offsets for the 3x3 neighborhood
    float2 offsets[9] =
    {
        float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-1, 0), float2(0, 0), float2(1, 0),
        float2(-1, 1), float2(0, 1), float2(1, 1)
    };

    // Collect luminance changes from neighbors
    for (int i = 0; i < 9; ++i)
    {
        // Calculate the new texture coordinate
        float2 neighborCoord = texcoord + offsets[i] / float2(view_width, view_height);
        
        // Clamp the coordinates to ensure they remain within texture bounds
        neighborCoord = clamp(neighborCoord, float2(0.0, 0.0), float2(1.0, 1.0));

        // Get the luminance change from the neighbor and store it
        luminance_changes[i] = TemporalLuminanceChange(neighborCoord);
    }

    // Calculate the average of the luminance changes while avoiding division by zero
    float total_change = 0.0;
    for (int i = 0; i < 9; ++i)
    {
        total_change += luminance_changes[i];
    }
    
    return total_change / 9.0; // Return the average change in luminance
}

// Function to calculate edge detection using the 3x3 Sobel filter
float SobelEdgeDetection(float2 texcoord)
{
    // Sobel matrices for horizontal and vertical edge detection
    const float3 SobelX[3] = { float3(-1, 0, 1), float3(-2, 0, 2), float3(-1, 0, 1) };
    const float3 SobelY[3] = { float3(-1, -2, -1), float3(0, 0, 0), float3(1, 2, 1) };
    
    // Initialize edge accumulation variables
    float edge_x = 0.0;
    float edge_y = 0.0;

    // Offsets for the 3x3 neighborhood
    float2 offsets[3] = { float2(-1, -1), float2(0, -1), float2(1, -1) };

    // Apply the Sobel filter
    for (int i = 0; i < 3; ++i)
    {
        for (int j = 0; j < 3; ++j)
        {
            // Calculate the texture coordinate for the current neighbor
            float2 offset = offsets[i] + float2(0, j);
            float2 neighborCoord = texcoord + offset / float2(view_width, view_height);

            // Clamp the coordinates to ensure they remain within texture bounds
            neighborCoord = clamp(neighborCoord, float2(0.0, 0.0), float2(1.0, 1.0));

            // Sample the depth value from the texture
            float depth = tex2D(DepthSampler, neighborCoord).r;

            // Accumulate the weighted depth values using the Sobel kernels
            edge_x += depth * SobelX[i][j];
            edge_y += depth * SobelY[i][j];
        }
    }

    // Calculate and return the magnitude of the gradient vector
    return length(float2(edge_x, edge_y));
}

// Function to generate n-rook patterns using Halton sequences
float2 GenerateNRooksPattern(int index, int num_samples)
{
    // Validate input parameters
    if (num_samples <= 0)
    {
        return float2(0.0, 0.0); // Return zero pattern for invalid num_samples
    }

    // Generate the pattern using Halton sequences for the specified base
    float2 pattern;
    pattern.x = (index + HaltonSequence(index, 2)) / float(num_samples);
    pattern.y = (index + HaltonSequence(index, 3)) / float(num_samples);

    // Ensure the pattern values are clamped between 0 and 1
    pattern = saturate(pattern);

    return pattern;
}

// Example implementation of CalculateContrast using the Depth texture
float CalculateContrast(float2 texcoord)
{
    // Sample depth values from the Depth texture to calculate contrast
    float depth_center = tex2D(DepthSampler, texcoord).r;
    float depth_left = tex2D(DepthSampler, texcoord + float2(-1.0 / view_width, 0)).r;
    float depth_right = tex2D(DepthSampler, texcoord + float2(1.0 / view_width, 0)).r;

    // Calculate contrast as the difference between max and min depths in the neighborhood
    float max_depth = max(max(depth_center, depth_left), depth_right);
    float min_depth = min(min(depth_center, depth_left), depth_right);
    
    return max_depth - min_depth; // Simple contrast measure
}

// Example implementation of CalculateColorVariation using BackBuffer texture
float CalculateColorVariation(float2 texcoord)
{
    // Sample colors from the neighborhood using the BackBuffer texture
    float3 color_center = tex2D(BackBuffer, texcoord).rgb;
    
    float total_variation = 0.0;
    
    for (int i = -1; i <= 1; ++i)
    {
        for (int j = -1; j <= 1; ++j)
        {
            if (i == 0 && j == 0)
                continue; // Skip the center pixel
            
            float3 neighbor_color = tex2D(BackBuffer, texcoord + float2(i, j) / float2(view_width, view_height)).rgb;
            total_variation += length(neighbor_color - color_center); // Color distance
        }
    }
    
    return total_variation / 8.0; // Average variation over neighbors
}

// Function to calculate visual complexity based on luminance change and neighborhood analysis
float CalculateVisualComplexity(float2 texcoord)
{
    // Calculate the luminance change in the neighborhood using the BackBuffer
    float luminance_change = NeighborhoodLuminanceChange(texcoord);

    // Calculate contrast and color variation using the Depth texture
    float contrast = CalculateContrast(texcoord);
    float color_variation = CalculateColorVariation(texcoord);

    // Combine the factors to determine overall visual complexity
    float visual_complexity = luminance_change + contrast + color_variation;

    // Clamp the result to ensure it stays within a reasonable range
    return saturate(visual_complexity);
}

// Function to calculate the offset of custom MSAA samples
float2 CustomMSAASample(int sampleIndex, int numSamples)
{
    // Validate input parameters
    if (numSamples <= 0 || sampleIndex < 0 || sampleIndex >= numSamples)
    {
        // Return zero offset for invalid parameters
        return float2(0.0, 0.0);
    }

    // Use Halton sequence or other approach to calculate jitter offset
    float2 sample_offset = GenerateNRooksPattern(sampleIndex, numSamples);

    // Transform the sample offset to the appropriate range and scale
    sample_offset = (sample_offset * 2.0 - 1.0); // Scale to [-1, 1]
    
    // Normalize by view dimensions to get the final offset in texture coordinates
    return sample_offset / float2(view_width, view_height);
}

// Function to calculate weight based on luminance change and edge strength
float CalculateWeight(float luminance_change, float edge_strength)
{
    return 1.0 / (1.0 + luminance_change + edge_strength);
}

// Function to normalize the accumulated color
float3 NormalizeColor(float3 accumulated_color, float total_weight)
{
    if (total_weight > 0)
    {
        accumulated_color /= total_weight; // Average the color
    }
    return clamp(accumulated_color, 0.0, 1.0); // Ensure the color is within [0, 1]
}

/*-------------------.
| :: Pixel Shader :: |
'-------------------*/

float3 MainPS(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    float3 color = float3(0.0, 0.0, 0.0);
    float total_weight = 0.0; // Variable to accumulate the weights

    // Determine the level of adaptivity per pixel
    float visual_complexity = CalculateVisualComplexity(texcoord);
    int num_samples = (visual_complexity > complexity_threshold) ? 4 : 2; // Reduced samples for testing

    for (int i = 0; i < num_samples; ++i)
    {
        // Calculate jitter offset per pixel
        float2 sample_offset = CustomMSAASample(i, num_samples);

        // Apply jittering to texture coordinates
        float2 sample_texcoord = texcoord + sample_offset;

        // Get and dilate motion vectors
        float2 velocity = DilateVelocity(sample_texcoord);

        // Update Segmentation History
        float4 segment_history = UpdateSegmentHistory(sample_texcoord);

        // Calculate the luminance change in neighboring pixels
        float luminance_change = NeighborhoodLuminanceChange(sample_texcoord);

        // Calculate edge detection using Sobel filter
        float edge_strength = SobelEdgeDetection(sample_texcoord);

        // Use weights based on luminance change and edge strength
        float weight = CalculateWeight(luminance_change, edge_strength);
        total_weight += weight; // Accumulate the total weight
        
        // Calculate the color without Gaussian influence
        float3 sample_color = CalculateEMAColor(sample_texcoord, velocity);

        // Integrate Segmentation History into Final Color Calculation
        if (segment_history.a > 0.0)
        {
            sample_color *= 1.0; // Keep the normal intensity 
        }

        // Adjust the final color based on the luminance change and clamping
        sample_color *= clamp(1.0 / (1.0 + luminance_change), 0.0, 1.0);

        // Adjust final color based on edge strength
        sample_color *= (1.0 + edge_strength);

        // Add the sampled color weighted by the calculated weight
        color += sample_color * weight;
    }

    // Normalize the accumulated color at the end of sampling
    color = NormalizeColor(color, total_weight);

    // Create intermediate pixels to reduce aliasing effects
    float3 left_color = tex2D(BackBuffer, texcoord + float2(-1.0 / view_width, 0)).rgb;
    float3 right_color = tex2D(BackBuffer, texcoord + float2(1.0 / view_width, 0)).rgb;

    // Final clamping to ensure color is within valid range [0, 1]
    return clamp(color, 0.0, 1.0);
}

/*-----------------.
| :: Techniques :: |
'-----------------*/

technique myTAA
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = MainPS;
    }
}

/*-------------.
| :: Footer :: |
'--------------/

