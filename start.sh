#!/bin/bash
`hexo clean && hexo deploy`
`git add --all .`
`git commit -m "update blog"`
`git config --global http.postBuffer 524288000`
`git push`
