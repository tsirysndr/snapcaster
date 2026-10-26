module CI.Release (releaseArgs, publishRelease, uploadRelease) where

import Prelude
import Dagger (Client)
import Dagger.Container as Container
import Dagger.Modules as Module
import Dagger.Query as Query
import Dagger.Types (Container, Directory, Secret, ReturnType(..))
import CI.Assets as Assets
import Data.Array (null)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff, throwError)
import Effect.Exception (error)

type ReleaseArgs = { assets :: Directory, tag :: String, token :: Secret, runId :: String }

releaseArgs :: Module.Arguments ReleaseArgs
releaseArgs = ado
  assets <- Module.argument "assets"
  tag <- Module.argument "tag"
  token <- Module.argument "token"
  runId <- Module.argument "runId"
  in { assets, tag, token, runId }

publisher :: Client -> Container
publisher client = Query.container client
  # Container.from "node:24-bookworm-slim"
  # Container.withExec [ "apt-get", "update" ]
  # Container.withExec [ "apt-get", "install", "-y", "--no-install-recommends", "gh", "ca-certificates" ]

release :: Boolean -> Client -> ReleaseArgs -> Aff String
release create client args = do
  files <- Assets.releaseFiles args.assets
  when (null files) $ throwError (error "No release assets supplied")
  let base = publisher client
        # Container.withDirectory "/assets" args.assets
        # Container.withWorkdir "/assets"
        # Container.withSecretVariable "GH_TOKEN" args.token
        # Container.withEnvVariable "GH_REPO" "tsirysndr/snapcaster"
        # Container.withEnvVariable "WORKFLOW_RUN" args.runId
  ready <- if create then do
    status <- Container.exitCode $ base
      # Container.withExecWith [ "gh", "release", "view", args.tag ]
          (Container.defaultWithExecOpts { expect = Just ReturnTypeAny })
    pure $ base # Container.withExec
      (if status == 0 then [ "gh", "release", "edit", args.tag, "--draft=false", "--prerelease=false" ]
       else [ "gh", "release", "create", args.tag, "--verify-tag", "--generate-notes", "--draft=false", "--prerelease=false" ])
    else pure base
  void $ Container.sync $ ready # Container.withExec
    ([ "gh", "release", "upload", args.tag, "--clobber" ] <> map ("./" <> _) files)
  pure "Release assets published"

publishRelease :: Client -> ReleaseArgs -> Aff String
publishRelease = release true

uploadRelease :: Client -> ReleaseArgs -> Aff String
uploadRelease = release false
