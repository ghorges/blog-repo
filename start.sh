#!/bin/bash
`hexo clean && hexo deploy`
`git add --all .`
`git commit -m "update blog"`
`git push`
