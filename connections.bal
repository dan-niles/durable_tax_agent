import ballerinax/ai.openai;

final openai:ModelProvider taxAgentModel = check new (openRouterApiKey, openai:GPT_4O_MINI,
    serviceUrl = "https://openrouter.ai/api/v1");
