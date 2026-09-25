import ballerinax/ai.mistral;

final mistral:ModelProvider taxAgentModel = check new (mistralApiKey, mistral:MISTRAL_SMALL_LATEST);
