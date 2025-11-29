import {
  logger,
  type IAgentRuntime,
  type Project,
  type ProjectAgent,
} from "@elizaos/core";
import { character } from "./character.ts";
import { character as famelizaCharacter } from "./fameliza.ts";
import authPlugin from "./plugin-auth.ts";

const initCharacter = ({ runtime }: { runtime: IAgentRuntime }) => {
  logger.info("Initializing character");
  logger.info({ name: character.name }, "Name:");
};

// export const projectAgent: ProjectAgent = {
//   character,
//   init: async (runtime: IAgentRuntime) => initCharacter({ runtime }),
//   // plugins: [authPlugin],
// };

export const famelizaProjectAgent: ProjectAgent = {
  character: famelizaCharacter,
  init: async (runtime: IAgentRuntime) => initCharacter({ runtime }),
  // plugins: [authPlugin],
};

const project: Project = {
  agents: [famelizaProjectAgent],
};

export { character } from "./character.ts";

export default project;
