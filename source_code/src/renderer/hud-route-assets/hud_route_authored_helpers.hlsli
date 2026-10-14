// Authored HUD blend helpers shared by the mod's composition shaders.
// Preserve input conventions, alpha treatment and effect ordering when editing.

float4 ScreenBlend(float4 ColorA, float4 ColorB)
{
	return (ColorA + ColorB - ColorA * ColorB);
}
float SoftLightBlendSingle(float InBaseValue, float InSwizzledValue, float InBlendValue, float MaxValue, float ThresholdValue)
{
	float ValueA=InBaseValue, ValueB=0;
	if (InBlendValue > ThresholdValue)
	{
		ValueA = 2.0f * InBaseValue * (1.0f - InSwizzledValue / MaxValue);
		ValueB = sqrt(InBaseValue) * (2.0f * InBlendValue - 1.0f);
	}
	else if (InBlendValue > 0.0f)
	{
		ValueA = InBaseValue * (1.0f - InSwizzledValue / MaxValue);
		ValueB = 0.3f * InBlendValue;
	}
	else
	{
		ValueA = InBaseValue;
		ValueB = 0.0f;
	}
	return (ValueA + ValueB);
}
float3 SwizzleSoftBlendColor(float3 InBlendColor)
{
	float3 SoftBlend = 0;
	if (InBlendColor.r > InBlendColor.g && InBlendColor.r > InBlendColor.b)
	{
		if (InBlendColor.b < InBlendColor.g)
		{
			SoftBlend = InBlendColor.bgr;
		}
		else
		{
			SoftBlend = InBlendColor.grb;
		}
	}
	else if (InBlendColor.g > InBlendColor.r && InBlendColor.g > InBlendColor.b)
	{
		if (InBlendColor.b < InBlendColor.r)
		{
			SoftBlend = InBlendColor.rbg;
		}
		else
		{
			SoftBlend = InBlendColor.grb;
		}
	}
	else if (InBlendColor.b > InBlendColor.r && InBlendColor.b > InBlendColor.g)
	{
		if (InBlendColor.r < InBlendColor.g)
		{
			SoftBlend = InBlendColor.bgr;
		}
		else
		{
			SoftBlend = InBlendColor.rbg;
		}
	}
	return SoftBlend;
}
float4 SoftLightBlend(float4 InBaseColor, float4 InBlendColor)
{
	float3 FirstSoftLightColor = SwizzleSoftBlendColor(InBlendColor.rgb) * FirstSoftLightOpacity * SoftLightColorScale.rgb;
	float3 SecondSoftLightColor = InBlendColor.rgb * SecondSoftLightOpacity * SoftLightColorScale.rgb;
	float3 SoftLightColor = FirstSoftLightColor + SecondSoftLightColor;
	float3 ThresholdColor = float3(0.5f, 0.5f, 0.5f);
	float3 MaxColor = float3(1.0f, 1.0f, 1.0f);
	float OutR = SoftLightBlendSingle(InBaseColor.r, SoftLightColor.r, InBlendColor.r, MaxColor.r, ThresholdColor.r);
	float OutG = SoftLightBlendSingle(InBaseColor.g, SoftLightColor.g, InBlendColor.g, MaxColor.g, ThresholdColor.g);
	float OutB = SoftLightBlendSingle(InBaseColor.b, SoftLightColor.b, InBlendColor.b, MaxColor.b, ThresholdColor.b);
	return float4(OutR, OutG, OutB, InBaseColor.a);
}
float4 BlendGlowToSceneCommon(
	float4 SoftLight,
	float4 DepthDeviation,
	float4 AdditionalGlow,
	float4 GlowCore,
	float4 BaseUI,
	float4 SceneColor,
	float IntensityN)
{
	float4 OutBlendedColor = SoftLightBlend(SceneColor, SoftLight);
	OutBlendedColor.a = 1.0f;
	OutBlendedColor += DepthDeviation + AdditionalGlow + BaseUI * (1.0f + IntensityN);
	OutBlendedColor = ScreenBlend(OutBlendedColor, GlowCore);
	return OutBlendedColor;
}
float4 BlendGlowToSceneMenu(
	float4 SoftLight,
	float4 BaseUI,
	float4 SceneColor)
{
	float4 OutBlendedColor = SoftLightBlend(SceneColor, SoftLight);
	OutBlendedColor.a = 1.0f;
	OutBlendedColor.rgb = OutBlendedColor.rgb * (1.0f - BaseUI.a) + BaseUI.rgb;
	return OutBlendedColor;
}
float4 BlendGlowToScene(
	float4 SoftLight,
	float4 DepthDeviation,
	float4 AdditionalGlow,
	float4 GlowCore,
	float4 BaseUI,
	float4 SceneColor,
	float IntensityN,
	bool bIsMenuMode)
{
	float4 result=0;
	if (bIsMenuMode) result=BlendGlowToSceneMenu(SoftLight, BaseUI, SceneColor);
	else result=BlendGlowToSceneCommon(SoftLight, DepthDeviation, AdditionalGlow, GlowCore, BaseUI, SceneColor, IntensityN);
	return result;
}
float GetIntentsityAdjustedByNeighborhood(Texture2D InTexture, SamplerState InSampler, float2 InUV, float2 InInvViewSize, float3 InLuminanceColor)
{
	float IntensityN = 10.0f;	
	float2 OffsetU2 = float2(InInvViewSize.x * 2.0f, 0.0f);
	float2 OffsetV2 = float2(0.0f, InInvViewSize.y * 2.0f);
	float4 Color21 = Texture2DSample(InTexture, InSampler, InUV - OffsetU2);
	float4 Color22 = Texture2DSample(InTexture, InSampler, InUV + OffsetU2);
	float4 Color23 = Texture2DSample(InTexture, InSampler, InUV - OffsetV2);
	float4 Color24 = Texture2DSample(InTexture, InSampler, InUV + OffsetV2);
	IntensityN *= dot(Color21.rgb, InLuminanceColor) * dot(Color22.rgb, InLuminanceColor) * dot(Color23.rgb, InLuminanceColor) * dot(Color24.rgb, InLuminanceColor);	
	return IntensityN;
}

