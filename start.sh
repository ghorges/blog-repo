#!/bin/bash
`hexo clean && hexo deploy`
`git add .`
`git commit -m "update blog"`
`git push`
