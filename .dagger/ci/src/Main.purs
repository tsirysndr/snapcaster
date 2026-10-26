module Main where

import Prelude
import CI.Runtime as Runtime
import CI.Release as Release
import Dagger.Modules as Module
import Effect (Effect)

main :: Effect Unit
main = Runtime.runModule
  [ Module.object_ "ProjectCi" {}
      [ Module.function "publishRelease" "Create or update a public GitHub release and upload its assets." Release.releaseArgs Release.publishRelease
      , Module.function "uploadRelease" "Attach assets to an existing release." Release.releaseArgs Release.uploadRelease
      ]
  ]
