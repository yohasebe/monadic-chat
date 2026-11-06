#!/bin/bash
# Third-party files the web UI serves from /vendor, pinned by version and hash.
#
# Format: "type,url,filename,sha256"
#   type:    css, js, font (vendor/fonts), webfont (vendor/webfonts) or pdfjs
#            (vendor/pdfjs; filename may name a folder under it)
#   url:     a versioned URL, so the same URL keeps returning the same bytes
#   sha256:  of the file as downloaded; nothing edits it afterwards
#
# Sourced by bin/assets.sh (host), scripts/download_assets.sh (Ruby image) and
# the packaging gates (through vendor_manifest), so all of them agree on what
# each vendor file is. A file that is not listed here does not ship.
ASSETS=(
  # CSS libraries
  "css,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.8/css/bootstrap.min.css,bootstrap.min.css,d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede"
  "css,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css,all.min.css,74005d7c17d4a02f2f25404ec0655d9bc2fdaa53166874c87d7b7eec69d9088a"
  "css,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/abcjs-audio.min.css,abcjs-audio.min.css,35a385f562654d2c7a16d37e638cecc2459a3e7dc19a989e52c34fc7e570851d"
  "css,https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/styles/github.min.css,github.min.css,3a9a5def8b9c311e5ae43abde85c63133185eed4f0d9f67fea4b00a8308cf066"
  "css,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css,katex.min.css,19095127357ed6d29fe0a63a6b000c913a89f7f1963b765dd3715e97c9852e75"

  # JS libraries
  "js,https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.8/js/bootstrap.bundle.min.js,bootstrap.bundle.min.js,e4fd49181388c48ec5040bd3fe66f57c29c8e67fcd8502b3354b96ec7ab47cc7"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/OpusMediaRecorder.umd.js,OpusMediaRecorder.umd.js,bcb406a8ed33ae1a2a1236707573efab3b62083823072187738ca8c46ffb3d7e"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/encoderWorker.umd.js,encoderWorker.umd.js,084c3fe284f45fb35e37652563fd8c72bb7b089c27e2acb72ab46d98008b241b"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/OggOpusEncoder.wasm,OggOpusEncoder.wasm,0329f6f157cda633f1a0c2cd021beecb23dc37f1dbc3f91b7eb64e03e7fb95f4"
  "js,https://cdn.jsdelivr.net/npm/opus-media-recorder@0.8.0/WebMOpusEncoder.wasm,WebMOpusEncoder.wasm,0d2f6d51da227fbe8a594a2fc1fc8eeb7a6ddd717da702d0305e734f5307b144"
  "js,https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js,mermaid.min.js,a43bc1afd446f9c4cc66ac5dd45d02e8d65e26fc5344ec0ef787f88d6ddb6f9e"
  "js,https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.min.js,abcjs-basic-min.min.js,d8efef92e7dd28d3b58911a5427ce26270404f4f4bcfed2aa83d9639f827bdf4"
  "js,https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js,markdown-it.min.js,38c70a1e7ca91ab40e2d9e6e60129851a717ed1c7d4acbbdd41bf9503791cf68"
  "js,https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.10.0/highlight.min.js,highlight.min.js,471ef9ae90c407af440fcdc48edfeeb562106b3267bd12d99071c162fb52ed32"
  "js,https://cdn.jsdelivr.net/npm/dompurify@3.4.12/dist/purify.min.js,purify.min.js,c45ba939765574f96cbf35ee9b6d89f73756a17921814425e74b82f7c54603ce"
  "js,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js,katex.min.js,e8d885505949f3a5f4abdd5dd0d53696bd1371ad26ffbf4f310dcd77c8cdae89"
  # diagrams.net serves only its latest viewer; the tagged copy in the drawio
  # repository is the one that stays the same.
  "js,https://raw.githubusercontent.com/jgraph/drawio/v29.5.2/src/main/webapp/js/viewer-static.min.js,viewer-static.min.js,7b713ba84a781bb3f56507de60b490d820fc91a912480f5b1ad1a2daef852de5"
  # maxGraph has no browser build to download; `npm run build:maxgraph` makes
  # vendor/js/maxgraph.bundle.js from the locked @maxgraph/core.

  # pdf.js (the work screen's PDF view), into vendor/pdfjs: the library, its
  # worker, and what it loads beside them (CMaps for fonts a PDF does not
  # embed, the standard fonts, the image decoders and the color profile).
  # PDF scripting (quickjs) is left out.
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/build/pdf.min.mjs,pdf.min.mjs,57456c8e0c81e46be31174b499ef77f2b9f5ee46d04412ba627320a36755d4c2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/build/pdf.worker.min.mjs,pdf.worker.min.mjs,9536359f1b8367850d485731ca1d5e45c159a7b7a0912325e539937aa21ceb18"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/LICENSE,LICENSE,0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-EUC-H.bcmap,cmaps/78-EUC-H.bcmap,d92a261336dc18b8c03a46eb4d462382d33f4338fa195d303256b2031434c874"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-EUC-V.bcmap,cmaps/78-EUC-V.bcmap,61670bebc4e4827b67230c054fd0d820d6e30c3584d02e386804e62bbedc032a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-H.bcmap,cmaps/78-H.bcmap,ece6415b853d61e1b2560165151407d35cf16e6556932b85a13ea75276b77402"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-RKSJ-H.bcmap,cmaps/78-RKSJ-H.bcmap,696b1f973c97623496703809eaaa5f9b40696c77540057413f4b826a08edfa7b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-RKSJ-V.bcmap,cmaps/78-RKSJ-V.bcmap,53cb6d560ab377da48cf65d6dcacb0bdb31f13fab7066c580de38c12a73a7ff9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78-V.bcmap,cmaps/78-V.bcmap,289000f02fd34872b6975503217f33abae6bee676e7d28f640473a67c8db1712"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78ms-RKSJ-H.bcmap,cmaps/78ms-RKSJ-H.bcmap,a2442595218f5f8bd8e1b42188e368587d876cfe0cc4cd87196f077c878f72e2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/78ms-RKSJ-V.bcmap,cmaps/78ms-RKSJ-V.bcmap,f8ddceba96bfd9d3740bd1789ee30d1f47c78371520a8084f71f7df58f19be0b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/83pv-RKSJ-H.bcmap,cmaps/83pv-RKSJ-H.bcmap,44040051ec818fe09b9703472bea72efd2759d5eeb5ff0d77c718d6bb5e6d1df"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90ms-RKSJ-H.bcmap,cmaps/90ms-RKSJ-H.bcmap,c13e043e85ff715b75bb03801e8fd0fb8f3a75e4a48496faa6baaf92b5b48ba1"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90ms-RKSJ-V.bcmap,cmaps/90ms-RKSJ-V.bcmap,499bb916ce1adbe4289b6e5811f4dc20eb238cdc2ffad20cf26ae56716885bab"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90msp-RKSJ-H.bcmap,cmaps/90msp-RKSJ-H.bcmap,7b8b3b8bbf821702e9a4df9f3596ce292380c8c1b0925dedadbb4e4b2d80498b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90msp-RKSJ-V.bcmap,cmaps/90msp-RKSJ-V.bcmap,6296c2b5c07dca8128e96d5296d621a3268803d4fa0e5812a21e52fe2802aacb"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90pv-RKSJ-H.bcmap,cmaps/90pv-RKSJ-H.bcmap,fb5103f03d3a34547e18d316e52b6d9b26e485c662999222f84d2ba54c2e4fa8"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/90pv-RKSJ-V.bcmap,cmaps/90pv-RKSJ-V.bcmap,7bcb5ad2ba55b9662ce379e16c2d9cc2b82d621a579807353741172e4af615c2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Add-H.bcmap,cmaps/Add-H.bcmap,a2ffab28b990998181bcca9b0e914bb2207820f100ae31d5c469444892e5ad8e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Add-RKSJ-H.bcmap,cmaps/Add-RKSJ-H.bcmap,b29f4b52e2465d0485856d5e69f1ba69927deb2848d8fd328c8035583b35bb7e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Add-RKSJ-V.bcmap,cmaps/Add-RKSJ-V.bcmap,2aa2232c283a3f5d0997c2834a36cead0b79ce2657944cfeed08140c293460ff"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Add-V.bcmap,cmaps/Add-V.bcmap,25125d3b1be64e86b2df5b3344170b45a42bcaa0b46e43a34314ef73c166e542"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-0.bcmap,cmaps/Adobe-CNS1-0.bcmap,8c65be9d51a9f269a547dc12460707aaf4031ab67ebe8a2900f4b4cc6b3e450e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-1.bcmap,cmaps/Adobe-CNS1-1.bcmap,73152bc1a59cc594b414ac6068be48e5512b96ae85920c40e32a99269fdb0c04"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-2.bcmap,cmaps/Adobe-CNS1-2.bcmap,a1b8d353bdef9584c820464e8f1c9e2013d64ebf433cba0aa831dddf515818c2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-3.bcmap,cmaps/Adobe-CNS1-3.bcmap,2ffc0c75c79fafde506163d3c08c390d183251009f3fbf6ae50d1167d14b9570"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-4.bcmap,cmaps/Adobe-CNS1-4.bcmap,98a1f470c878c6b9691a4d7aef776af8ac9b55f5587c9fafa00547f3bf655716"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-5.bcmap,cmaps/Adobe-CNS1-5.bcmap,ddd6e29955eb8cb545f2ebd09c628c3bbda5023256eda1b728f743c75fb77829"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-6.bcmap,cmaps/Adobe-CNS1-6.bcmap,317bb2db71e0e5b7b0c47b75de1da915c2e22f65f0c0861507f9ca7ba238f8a2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-CNS1-UCS2.bcmap,cmaps/Adobe-CNS1-UCS2.bcmap,e665837f2197c6bd08cd8955ad4d6932cee2398e2e328b25b00e6bfb3bd72af9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-0.bcmap,cmaps/Adobe-GB1-0.bcmap,8b81cce8a11d510e505704953cfa4e4ab080c1a0cab991145a3512ee433946b9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-1.bcmap,cmaps/Adobe-GB1-1.bcmap,0426983081788ec7202703e71f1efa4b860f75b936994236010b39d89251a81e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-2.bcmap,cmaps/Adobe-GB1-2.bcmap,e67b37a83b160ab3831306a71a605893b24454ee81ac9b6123bf2d3984d268d5"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-3.bcmap,cmaps/Adobe-GB1-3.bcmap,aa299afc3e12a28726147305f191be28c7498078c8b182ece7886ac79cd99078"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-4.bcmap,cmaps/Adobe-GB1-4.bcmap,8fbd7d74c2ddb1350c1cecce54a73fde3f5453093d4bed445283ec0033d2097f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-5.bcmap,cmaps/Adobe-GB1-5.bcmap,c22cb2fcff24112fa31dab2111bdc51957006576d31aad5a25e67793ac01428c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-GB1-UCS2.bcmap,cmaps/Adobe-GB1-UCS2.bcmap,20507620260c0c935c35afc1e70e5888aa7125d5ec7ffc03cef1959feb2c1641"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-0.bcmap,cmaps/Adobe-Japan1-0.bcmap,464f08905236f5703b1f5cf8358767c8b18e6bcc808840d081f1de2c7ab38134"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-1.bcmap,cmaps/Adobe-Japan1-1.bcmap,4c823848722187d1ffe75ae3f5f9126ccd2d7895a05fad14c919fb119e037008"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-2.bcmap,cmaps/Adobe-Japan1-2.bcmap,7810fb808e367e70429e90a9478fe6a3fdc3e214f25c7582ce9c2da6a242315c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-3.bcmap,cmaps/Adobe-Japan1-3.bcmap,84deb1828711ad3d390c9899c38abce1bf619d65ff7bf1a326ec95acc45f08f8"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-4.bcmap,cmaps/Adobe-Japan1-4.bcmap,3f8a4f974919c2b8bae5d10175ffa2673be140481e00840542c85d48ef184067"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-5.bcmap,cmaps/Adobe-Japan1-5.bcmap,1d3ce4ff28d977f8cf37a912ae4ec811f4175c3167b1ec0b2567feec3e79e1db"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-6.bcmap,cmaps/Adobe-Japan1-6.bcmap,5609797b9401b30be72ef9645da62a87829f058c3be4b5c623383119f584b1d9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Japan1-UCS2.bcmap,cmaps/Adobe-Japan1-UCS2.bcmap,66c5d0dc4964f4093e77b194023f3a0f689324028ec8330e1e1d0570bcba7c2f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Korea1-0.bcmap,cmaps/Adobe-Korea1-0.bcmap,dfb8c3874f0e5a8c3acf597d2c12d2b63e90bc5e4f0fce990ec4c56077d80b32"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Korea1-1.bcmap,cmaps/Adobe-Korea1-1.bcmap,62f277b7b1c441c007797ae707d5c37258d029ce4661a2b911e2e1ee35e6adc1"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Korea1-2.bcmap,cmaps/Adobe-Korea1-2.bcmap,1d77068af462f96d7ad28ad7e7d43eef6423c685b479d7dc25ff5df38db0380d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Adobe-Korea1-UCS2.bcmap,cmaps/Adobe-Korea1-UCS2.bcmap,857b723088be97255053562bfa41bd1075a7f7910d3bab59a0645c8bbc7060ff"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/B5-H.bcmap,cmaps/B5-H.bcmap,718ad0ffbef4c34f8f3f31292c462e519cd567a5511fc8b346c60010d64f4ef9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/B5-V.bcmap,cmaps/B5-V.bcmap,b5c37383517477620ced927b6b4ffd4f4cc6230d8051b5b46a21d6768e07f7d8"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/B5pc-H.bcmap,cmaps/B5pc-H.bcmap,bab6028aead1d6149400e904ab10cfd319082d826473ed4c582c8eeed920f17e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/B5pc-V.bcmap,cmaps/B5pc-V.bcmap,41543142b9767f3b76133899fc8453282b01ad3c653acaeea42d78c5a7d08c63"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS-EUC-H.bcmap,cmaps/CNS-EUC-H.bcmap,e8f89cd61e6486b948205da46499d659ed0aed949b7095fd3c8e95ffe2b0e7a9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS-EUC-V.bcmap,cmaps/CNS-EUC-V.bcmap,cae422bec2ac6dbe86bf921cec942bacd2d0b733ffcca5f91b3ba14e917025a0"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS1-H.bcmap,cmaps/CNS1-H.bcmap,e8487971ab20cd16f3de3e8ac56ec994b72b658ad113f2818239dfd5108f501a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS1-V.bcmap,cmaps/CNS1-V.bcmap,42df8076aaa7574505e7304af83a3323ec032c4177d64b1309db8c043d594a8a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS2-H.bcmap,cmaps/CNS2-H.bcmap,bc6024d274d440f0625c69e25f37036ef6cb6689432ceaa160d3432a2a716ca7"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/CNS2-V.bcmap,cmaps/CNS2-V.bcmap,2e4f70a8afd23a121030fc2e5b5f3816e903b11e7ba8b8c09654b31c80399c38"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETen-B5-H.bcmap,cmaps/ETen-B5-H.bcmap,87ee6b3f5bfda5fe26fa35431264c7d73070d10dbbf398a75185d63ae322c18d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETen-B5-V.bcmap,cmaps/ETen-B5-V.bcmap,47dc0d2c21e3bde317947aec1675ceabc1d5460a60bf9c24334b8c407a17172c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETenms-B5-H.bcmap,cmaps/ETenms-B5-H.bcmap,d5f5a73da4173b7da9a3a20e16f26f9cd5d12deb1553409919e0cec6fd37fdee"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETenms-B5-V.bcmap,cmaps/ETenms-B5-V.bcmap,18252fca90f472f479af1bddd60d6ab51c8e1b55dcf6845951426504934543e0"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETHK-B5-H.bcmap,cmaps/ETHK-B5-H.bcmap,d2f10fa519336bc4efcc7b6deb9604b75429946b40d82e311cb3a97a1994c89a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/ETHK-B5-V.bcmap,cmaps/ETHK-B5-V.bcmap,1fea3fd0d9f0f679f80505800851ef2e4131d81127e18c006938ffa2f4c8b247"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/EUC-H.bcmap,cmaps/EUC-H.bcmap,f9939cd57fccdc65c5d9f4c205fd497ebdbd283643308da5663801a8c1d9c595"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/EUC-V.bcmap,cmaps/EUC-V.bcmap,1283a50a706507c4436da83ede9ad7a4440be25378f2e96f6c81a430081426a3"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Ext-H.bcmap,cmaps/Ext-H.bcmap,4000ed4e61a1c668ef453bbd0603cfa383defa793abd46a57ed870d7f527350b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Ext-RKSJ-H.bcmap,cmaps/Ext-RKSJ-H.bcmap,e0d2f0df337660e73813238dd4a725f11f0621b90f3273857db253d0e7694caa"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Ext-RKSJ-V.bcmap,cmaps/Ext-RKSJ-V.bcmap,f617a22b6d67febb187990952006c91a9f5a4db21155d268c656252d0c21985d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Ext-V.bcmap,cmaps/Ext-V.bcmap,c2087fb845a9e3acea0c2922cd40e6af67e11957bec74dcd597f1285edd490ce"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GB-EUC-H.bcmap,cmaps/GB-EUC-H.bcmap,928bad06fd84a48f5ba7150d7716609119fb660f2aaa73eccad81ddab9b9d203"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GB-EUC-V.bcmap,cmaps/GB-EUC-V.bcmap,a9ad88ac2479da529b16dc48abc5952332e27bc355335f91df5729a587533324"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GB-H.bcmap,cmaps/GB-H.bcmap,1018c777a8910b5bb46d7d54a4aee9d51ca5cff8addb2b41c969d9101cb3fd1c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GB-V.bcmap,cmaps/GB-V.bcmap,0b96789143c0bbf9f1641ae7165b3456dccd14dabffcbb0bd654d5bf6f94f863"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBK-EUC-H.bcmap,cmaps/GBK-EUC-H.bcmap,2103fed28650ede096a2281104a1a8a4304dae0db414342c636867522307123b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBK-EUC-V.bcmap,cmaps/GBK-EUC-V.bcmap,a7fd35dd14d9dbdb955f34e6c0630618b6620dfd09d4283b2f65a65ce77fcaea"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBK2K-H.bcmap,cmaps/GBK2K-H.bcmap,3d919ae72af16c5cc6846ec87a4326a9f125e493c59d3628429d35c2c95fe8c4"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBK2K-V.bcmap,cmaps/GBK2K-V.bcmap,b927fdfd595c07ce9158bf2ec13f4641b2e83b01c70989dadfabd6ed7c6ac2dc"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBKp-EUC-H.bcmap,cmaps/GBKp-EUC-H.bcmap,d15ebd8e81fb4fe8a244f1b1e877922e03500ac69eddf5001093e502430451d2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBKp-EUC-V.bcmap,cmaps/GBKp-EUC-V.bcmap,fdc736d46e642625dccc8ad8c59f2c69fc7db7a13f2e799c6c6b779e707bb97a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBpc-EUC-H.bcmap,cmaps/GBpc-EUC-H.bcmap,3c4a4eb82f05abe51f6650985c630e180438bfdd491318f5d20d2ec29236e1c3"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBpc-EUC-V.bcmap,cmaps/GBpc-EUC-V.bcmap,215bdfa2842705624b4cf4cd29b8e3c720f1e192365e0305c11030a424c84d7c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBT-EUC-H.bcmap,cmaps/GBT-EUC-H.bcmap,dc5f44e48a39f3367ae28665027d8ab1d8cedb5a9dcc5068a900acd6709f60f9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBT-EUC-V.bcmap,cmaps/GBT-EUC-V.bcmap,a1ad24e63653b8aa388c18fa5e498f007564e43dde699a9f91ccb4645c999be8"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBT-H.bcmap,cmaps/GBT-H.bcmap,8afda745a505763f3ff54c8126eeb48ef376ea9ed07d9f42ff9a22c5c547ec57"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBT-V.bcmap,cmaps/GBT-V.bcmap,cdc2ec5c3c7c7033290c9a8894878202f08674eb9b1ae7d36218430326768771"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBTpc-EUC-H.bcmap,cmaps/GBTpc-EUC-H.bcmap,7b23e2f7bfdb6c918f567b7324bf858f398bd8cd5f268d74ece19a3c91bf4f32"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/GBTpc-EUC-V.bcmap,cmaps/GBTpc-EUC-V.bcmap,d7a1b13ead9ab511cf2cd01de6ce8b02aa8e8767e84895337d7a3b67f039f93b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/H.bcmap,cmaps/H.bcmap,a0233e21047ec00b852125b243cbcf30abee511155b6d8159c24f944384bc9ee"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Hankaku.bcmap,cmaps/Hankaku.bcmap,b454701f7aecd7856769016dfd04ca64280a060f2c67a2466d50b4395d24974e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Hiragana.bcmap,cmaps/Hiragana.bcmap,2ed669394756dd9458651cd9995ab29ab691ecb7686659003306cdf22767a414"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKdla-B5-H.bcmap,cmaps/HKdla-B5-H.bcmap,5242bce18fb13ab4cc59b146a03eba36e4ce42667eeff09e10981a9d2aa4996b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKdla-B5-V.bcmap,cmaps/HKdla-B5-V.bcmap,2e0537f786c0791d41a925f72bad2d4e7268aa6cbf15a1400a722672cec38e2c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKdlb-B5-H.bcmap,cmaps/HKdlb-B5-H.bcmap,fdc8159984bf5dbe475c0d5dfcb621ecee4dea07c38c668bd77f4c679e23b9b3"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKdlb-B5-V.bcmap,cmaps/HKdlb-B5-V.bcmap,b249eb9dcb915ab45057c5d4d7aa55ef88d0efbb092af6bae0b2d4705d139abf"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKgccs-B5-H.bcmap,cmaps/HKgccs-B5-H.bcmap,ab64c7fc5e9b2e97750cc4f269b0da14fd8649e49151b7598c8df86599bac591"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKgccs-B5-V.bcmap,cmaps/HKgccs-B5-V.bcmap,02ebdf7cdffb5395fb21091cd58a013a18ae5388922822f9dc6292ef16b98956"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKm314-B5-H.bcmap,cmaps/HKm314-B5-H.bcmap,bfd8bbde6b36a9da4c1c902c74121a30d9807a7079a00eeea218be6adc223cef"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKm314-B5-V.bcmap,cmaps/HKm314-B5-V.bcmap,2a64a815cfb6fdd480674a868762e3d161fda17543b20c9209978559f0667164"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKm471-B5-H.bcmap,cmaps/HKm471-B5-H.bcmap,49d7c037758826b5b6c0fa329c35bbf25d3943197754e72ecd30c6fb04d745e6"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKm471-B5-V.bcmap,cmaps/HKm471-B5-V.bcmap,be24c109e78aa4fe3c1f27d30aab3ed0741e783fa1b6b6c2719741072b54b132"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKscs-B5-H.bcmap,cmaps/HKscs-B5-H.bcmap,08599378f41d96b40537adef6e6edcc4a787bc63f5accf47c026df4905a13914"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/HKscs-B5-V.bcmap,cmaps/HKscs-B5-V.bcmap,d073542b7dad1c4cbf01c1af5f0cd13218d1281a491956e310c55702fc8705c4"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Katakana.bcmap,cmaps/Katakana.bcmap,3b6ca6642fbf8822da00d5e58a8aa275216d5c32dbf2bd73e934197fc9fc5c53"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-EUC-H.bcmap,cmaps/KSC-EUC-H.bcmap,6784e16dbc5861c036c23d3e55f0d4ba0975a3e464da0ee8e49bcfff0be070c4"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-EUC-V.bcmap,cmaps/KSC-EUC-V.bcmap,fdb36bad85e9924823d49db374067988e024cf80fc894711f2c9178951cbbe95"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-H.bcmap,cmaps/KSC-H.bcmap,c1f6d61f1d3304fd539a65ae72624fa567ecc3853bf52e283958a7a2515b3eee"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-Johab-H.bcmap,cmaps/KSC-Johab-H.bcmap,939993d213f68db763bf156217c217ae23af082b91a0eacecf3d11eb4ff8ef8c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-Johab-V.bcmap,cmaps/KSC-Johab-V.bcmap,5d61967aac0e666def721e8b8d0fed8f95a879a14f2e76ce516c3d11c621e519"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSC-V.bcmap,cmaps/KSC-V.bcmap,d7da5afd9f1fe74816d79c9325f0139a4efb6438664ebfdf9a7aa92f3034360f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCms-UHC-H.bcmap,cmaps/KSCms-UHC-H.bcmap,5b70d8f6a4fa9e2283dc649f0ff95d906d56efbee50a20e8d2faec3a8fed078e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCms-UHC-HW-H.bcmap,cmaps/KSCms-UHC-HW-H.bcmap,a5e6ba22aceb02fdedee11bfb9ed138463d89e85b87810b9f075b469d936f8ec"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCms-UHC-HW-V.bcmap,cmaps/KSCms-UHC-HW-V.bcmap,890332a6a26880d463a12f2a6ff048bf9cf7e45077cfb1ca8815b89baa7bf411"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCms-UHC-V.bcmap,cmaps/KSCms-UHC-V.bcmap,1631b531c9a40c8cbe24c2317dba107362e49fa6e18af620414d627c111d570c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCpc-EUC-H.bcmap,cmaps/KSCpc-EUC-H.bcmap,709480682c55cedbb0124b9960d78e28febeee0df2e34607d61aac6601647ec7"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/KSCpc-EUC-V.bcmap,cmaps/KSCpc-EUC-V.bcmap,031707887d6fc2378a36cdb6775334fd7a236c3f95048d8436abf43fe26fc49d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/LICENSE,cmaps/LICENSE,aa92ab5a472974865a96fd4a4e9c13bb41bf6fe1b309cb6b8da48bc9e19839a2"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/NWP-H.bcmap,cmaps/NWP-H.bcmap,286c6c9e335da330928a01edc3c97a3a623f1f7f3c42762b0a7dc2f651b1a78f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/NWP-V.bcmap,cmaps/NWP-V.bcmap,3a75fb7b59adfb172710758c425d8ac6c93fd5360a64dd4afd5dd04e60ab4b4d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/RKSJ-H.bcmap,cmaps/RKSJ-H.bcmap,a70de61a22a898f693f02cc011c3e3cff2e10aaa7cddb4661e456a21ae859f78"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/RKSJ-V.bcmap,cmaps/RKSJ-V.bcmap,68c1a64506471a524ea5cfc3b3a9f8f70031989a6bd95427b1351f33ccf50b06"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/Roman.bcmap,cmaps/Roman.bcmap,1c6b3ef9d9e5cb1aa329142ce9414b90f9b6d7f9182a2a9e927378dab8f0d43f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UCS2-H.bcmap,cmaps/UniCNS-UCS2-H.bcmap,779428116752f34e2490a1941d24e4634c71e3c22d053b811d2090ae2fb3c704"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UCS2-V.bcmap,cmaps/UniCNS-UCS2-V.bcmap,1e5cc184b850ea44abc2df8ae5674279df668e8edf5e2a1a2ea2bd77adbd280f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF8-H.bcmap,cmaps/UniCNS-UTF8-H.bcmap,2f2a742bcd1a84a148a4a518b9eed51a8f9c6ca5ed3bc5e2e41fff97de5dc2d8"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF8-V.bcmap,cmaps/UniCNS-UTF8-V.bcmap,b7c3f10780a8c62dd1c8ff6c30dc1e4e23b6cdc87c3a96fcd514cc98ffd3af9d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF16-H.bcmap,cmaps/UniCNS-UTF16-H.bcmap,32ff139b3c7b91d6ad25f994701f3ce7b242906022c418fd73e6493fc228bfe5"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF16-V.bcmap,cmaps/UniCNS-UTF16-V.bcmap,278eb1e68d1a236c60ef59472cf0176ee0d45f364285e76ca12419a08d46fb9a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF32-H.bcmap,cmaps/UniCNS-UTF32-H.bcmap,bf26eb67fe19ee5ba915799e80ca72408400aa8342fdf6a244a4f44de8f97336"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniCNS-UTF32-V.bcmap,cmaps/UniCNS-UTF32-V.bcmap,f7da3caf83ceb1cb37936fa10700d9ba6e9c3f72c5bc9724e3ac79bff0c0179e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UCS2-H.bcmap,cmaps/UniGB-UCS2-H.bcmap,9201569b402e81ad8860650bd86350c4fa28e5dd5971f05fcacaf40f51de18ed"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UCS2-V.bcmap,cmaps/UniGB-UCS2-V.bcmap,f10282335e4d64203bc2a653a3a47d745ec76c8ae04549f4d50180c1899be216"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF8-H.bcmap,cmaps/UniGB-UTF8-H.bcmap,f217b439c80ee5fa1bc2cf6d1defcc319f8d84483d166a00ee199e05a68588df"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF8-V.bcmap,cmaps/UniGB-UTF8-V.bcmap,a64df947632878eacc532fa193c735c92a383b7d66e6f8374ac193af7c64fc63"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF16-H.bcmap,cmaps/UniGB-UTF16-H.bcmap,386fd39581245c034da016a92d23f3df1117d169f996100050b264fc09a84e35"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF16-V.bcmap,cmaps/UniGB-UTF16-V.bcmap,0473cfbba612b92dd9918f0ff8aee9112897c48e0ffdc0eb82da3144ed8ea84a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF32-H.bcmap,cmaps/UniGB-UTF32-H.bcmap,f48a145dc4e3ed1dca1dde7111716a72306a2a4191ab05c6bae3a5c3a961cd2f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniGB-UTF32-V.bcmap,cmaps/UniGB-UTF32-V.bcmap,106acc49b7118bdef944e32107b4f348238f3929a0a15d3b7aab7b9101535993"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UCS2-H.bcmap,cmaps/UniJIS-UCS2-H.bcmap,ad2352f40870880fbf7f8ee5abadff743fbd025fbf9830b8ada472d1c5e4da0b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UCS2-HW-H.bcmap,cmaps/UniJIS-UCS2-HW-H.bcmap,16e87edca954177c0881c874859d6783220925d821b5cdfb8755b61ebd93f9ce"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UCS2-HW-V.bcmap,cmaps/UniJIS-UCS2-HW-V.bcmap,1973457e2c0192819947e56068625b34fb9a72ecc8a476ce6d7eaae5f73e2e5c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UCS2-V.bcmap,cmaps/UniJIS-UCS2-V.bcmap,42a133d8e2ce9dd6d2288018e01592d2bf2435b326d39b94ea0b6e6a44ac33d3"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF8-H.bcmap,cmaps/UniJIS-UTF8-H.bcmap,798fb0bf06ab0788d1f6a91c2db7de581612eef03c628f10e8f7ecd8f70ab448"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF8-V.bcmap,cmaps/UniJIS-UTF8-V.bcmap,1021611424f913b2df0bfdbe94bd327c04e224ec89d8e821c6501ea3d21f4265"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF16-H.bcmap,cmaps/UniJIS-UTF16-H.bcmap,f6a89c5688978548c83fcee990e205bc63c74274d5c69b49032a3bd4c49a05ee"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF16-V.bcmap,cmaps/UniJIS-UTF16-V.bcmap,c67126fc7c73850855186bb0d6482ac0a365057e0b58778c4ab9f234683fef53"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF32-H.bcmap,cmaps/UniJIS-UTF32-H.bcmap,96195950ce0fe24443d8eb426fa6b88534ec421d7bef9046f0b2362809cfba73"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS-UTF32-V.bcmap,cmaps/UniJIS-UTF32-V.bcmap,ed4dafda402bdd19c4d5d8bf2ab41473c0f86f384552b4c7b963d6627daedeb1"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF8-H.bcmap,cmaps/UniJIS2004-UTF8-H.bcmap,691c614ce432b3e62486efb54e5c84c6da5afe9b51b21253bde4758feb484183"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF8-V.bcmap,cmaps/UniJIS2004-UTF8-V.bcmap,40a8c7ea2d46711c5f78fc9a878a7db68b1543ba5cd60ecf14f519a2deb829b7"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF16-H.bcmap,cmaps/UniJIS2004-UTF16-H.bcmap,710a32d7cb43fd6bd9dbf30da5971f8c941590f74441e208d852c2be0e74cc97"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF16-V.bcmap,cmaps/UniJIS2004-UTF16-V.bcmap,3b149aff5c5707b57fb3215d1775852c8b1f413ec0f679ea628f25cf87fe098d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF32-H.bcmap,cmaps/UniJIS2004-UTF32-H.bcmap,8d2658e18741af7937d586a57c89729a6fec0d86121197c1f8518aa58b29cdfb"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJIS2004-UTF32-V.bcmap,cmaps/UniJIS2004-UTF32-V.bcmap,6dd475782f2897648a683c48b2fa015a15b8f06856760bddc8a17a63f418bacb"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISPro-UCS2-HW-V.bcmap,cmaps/UniJISPro-UCS2-HW-V.bcmap,6826f94d789d7bf1960668c1c5819c34c9585c1b23152fbc19ee81c7df08524b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISPro-UCS2-V.bcmap,cmaps/UniJISPro-UCS2-V.bcmap,493de9fd1a08f7946065d8ab58f0c3c9fe489f5a0f109f2d05a3169b4bd5789f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISPro-UTF8-V.bcmap,cmaps/UniJISPro-UTF8-V.bcmap,6181d382cf736c5e09492e8be9f26f31fa25b7462253f23ab16646af432cad81"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISX0213-UTF32-H.bcmap,cmaps/UniJISX0213-UTF32-H.bcmap,692044e1fb33445668632bc9fe7386805c624864be1ddeb29d65bb0c99fc630c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISX0213-UTF32-V.bcmap,cmaps/UniJISX0213-UTF32-V.bcmap,dd54e16ca7bffb3a886242549b2bf7d78a277087f7c60d2636f118c21a5b0646"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISX02132004-UTF32-H.bcmap,cmaps/UniJISX02132004-UTF32-H.bcmap,f80ea5a989be30ccda5a8804baef6d3b4b044d2b339bf8b31c671b2466171cf6"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniJISX02132004-UTF32-V.bcmap,cmaps/UniJISX02132004-UTF32-V.bcmap,94c22bd99e771c5fbe0dd8dc39850570d4db0075074aca13e272813edd7cc57f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UCS2-H.bcmap,cmaps/UniKS-UCS2-H.bcmap,a1081396ab4adb6f4a5b6c15f896963c244c1c9bcb65ce5616d06096a1b9811c"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UCS2-V.bcmap,cmaps/UniKS-UCS2-V.bcmap,6cab547431958fbdc1d401d06ebd4dd61a73f5509a10f974df32bcbca11a2e43"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF8-H.bcmap,cmaps/UniKS-UTF8-H.bcmap,3fac9c65145f72d7d42157a3b9c5ed6904632184e6a0888f2b828699afd2002f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF8-V.bcmap,cmaps/UniKS-UTF8-V.bcmap,9ecc6cf30dd354b9778ddba163b6cc7302b087ce9f39d1ba73472d2b75ed13ca"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF16-H.bcmap,cmaps/UniKS-UTF16-H.bcmap,42d35b396286499dfae1737a07adb3a64500df37b426580bfb1d3ea872938519"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF16-V.bcmap,cmaps/UniKS-UTF16-V.bcmap,5bdb7390c80dcc136cb47d41dc7460082560969c17322ee739fe3020fb642410"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF32-H.bcmap,cmaps/UniKS-UTF32-H.bcmap,3a01ec51ed1b828101351e337ffb8250abe11880032e5210f881170fed2588de"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/UniKS-UTF32-V.bcmap,cmaps/UniKS-UTF32-V.bcmap,dfda895eceaed081af030dbbb962b49629eea817fc3c02bae15db93d0c68acd7"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/V.bcmap,cmaps/V.bcmap,b9ad1c0c09ff14bca52f9a28a9767eb857ad0e8946e64ba14c7387a7eb69866a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/cmaps/WP-Symbol.bcmap,cmaps/WP-Symbol.bcmap,543923bead225732aba30976690ee89095a19628277b5863efecc2c728d5d7bf"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/iccs/CGATS001Compat-v2-micro.icc,iccs/CGATS001Compat-v2-micro.icc,73e1ba37d2bad5bab2a964f40a9eed96209666efc067c3322626214bbef234a0"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/iccs/LICENSE,iccs/LICENSE,286e4fd7b447330b2c88e23890e3cd0a9d38cb398d4a59cb247f578ccbda3213"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitDingbats.pfb,standard_fonts/FoxitDingbats.pfb,845c752392b6c914fb989c75a08b7792b88f542d2499042ef2889f8c814a16ed"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitFixed.pfb,standard_fonts/FoxitFixed.pfb,b6c8fe53f134b8b6d4578cd2d544df4cee9624c4efa8d51a560fb40ea296101b"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitFixedBold.pfb,standard_fonts/FoxitFixedBold.pfb,f1b7159702973f54fc86254ea38bcf3712b2a736eb3a0995751e9f4bb45ad603"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitFixedBoldItalic.pfb,standard_fonts/FoxitFixedBoldItalic.pfb,8a000945843bd31add06aee63bf9fd41b7578b4f3242a4b7cd46349ad9d24d4d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitFixedItalic.pfb,standard_fonts/FoxitFixedItalic.pfb,5007faf8320fa1fcc08b8894b356ad976f60b992ba29ee5272578bbdebaf3876"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitSerif.pfb,standard_fonts/FoxitSerif.pfb,4f57d2b9d884af8f907bf22df6019b52d86cbf6214fdbd02b1ae05472a543f35"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitSerifBold.pfb,standard_fonts/FoxitSerifBold.pfb,0bdf4b04e964139818d51eda03d566ba999fc3ba2421b1c6c51f9dc969022e80"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitSerifBoldItalic.pfb,standard_fonts/FoxitSerifBoldItalic.pfb,a406cac82583bf98175cb62c87ed5e95c45fbb34eece63a10b0a13e793cb2e10"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitSerifItalic.pfb,standard_fonts/FoxitSerifItalic.pfb,610ae0687198045c4db5d1a6650fd5e92536631706382eb8b72e38df578d0ae9"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/FoxitSymbol.pfb,standard_fonts/FoxitSymbol.pfb,47967d055530e7357088a08403115425643ec2cdfd6201ba8af0fbd7116c1539"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LiberationSans-Bold.ttf,standard_fonts/LiberationSans-Bold.ttf,361c61b82d575c5c35fd9157fda8b0194bcfcd0d88ea8521a4fb5dd53d33dddc"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LiberationSans-BoldItalic.ttf,standard_fonts/LiberationSans-BoldItalic.ttf,a224075ac17495ad0a3af3bc0a419ac0704a8b3fd1095456201fb9b095fc281d"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LiberationSans-Italic.ttf,standard_fonts/LiberationSans-Italic.ttf,832b4406dbef23628800d3aaad21048534ac84d7e3ad955be83b8172ed8ef512"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LiberationSans-Regular.ttf,standard_fonts/LiberationSans-Regular.ttf,f8ace1f892b2bd9dc1792ba7f097fa7588f84fed48321480e04de5390828221f"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LICENSE_FOXIT,standard_fonts/LICENSE_FOXIT,b578cdd2345840ada550bd12519533812320d5f1d21cf4c1c7e1b1b0a31c98b7"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/standard_fonts/LICENSE_LIBERATION,standard_fonts/LICENSE_LIBERATION,d2c4d5b3e115a519cb58eb691aa64538397e2611f9ebe801392cf9667997e7dc"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/jbig2.wasm,wasm/jbig2.wasm,466f45c2a61a698152fb5400c27e56ff2ceb73dcb71fde3fc366a502308eaab0"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/jbig2_nowasm_fallback.js,wasm/jbig2_nowasm_fallback.js,68686ced624a48c42f84cdaa482ec44b72b0de4dc84a0df903af1fb7b45b5d9a"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_JBIG2,wasm/LICENSE_JBIG2,9e66b7f1b934a28b37f3bc4dac97915de1674271e79a0a88182a18ed9731b4d1"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_OPENJPEG,wasm/LICENSE_OPENJPEG,a6af136f3e15038a666b61f376612a07d9a4e48cb7c01adbf3e33b3f14ab49b6"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_PDFJS_JBIG2,wasm/LICENSE_PDFJS_JBIG2,aad3cce09842e00e9e11ad5e8fef8cc02fbc3a3768fe2f007443b9cee37aaee5"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_PDFJS_OPENJPEG,wasm/LICENSE_PDFJS_OPENJPEG,717fc62da03292dbb4dd0c8280bd4ce7bb8550dcf31d772bc93455fb50313425"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_PDFJS_QCMS,wasm/LICENSE_PDFJS_QCMS,508a77d2e7b51d98adeed32648ad124b7b30241a8e70b2e72c99f92d8e5874d1"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/LICENSE_QCMS,wasm/LICENSE_QCMS,36d847ae882f6574ebc72f56a4f354e4f104fde4a584373496482e97d52d31bc"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/openjpeg.wasm,wasm/openjpeg.wasm,95e5002597af0824004aa57b1900fe019715db389e37640b1e58395e42f00cc5"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/openjpeg_nowasm_fallback.js,wasm/openjpeg_nowasm_fallback.js,9047b34b6bc142d85e4b0aa1b08b0b9baad4c6f8b7ac87641b9e8f90eb6fd23e"
  "pdfjs,https://cdn.jsdelivr.net/npm/pdfjs-dist@6.4.299/wasm/qcms_bg.wasm,wasm/qcms_bg.wasm,663d86126d5f5fcb1c61490f94353e2a8375660b8c5498ab3ebab5a34b08800e"

  # Font Awesome Webfonts
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-solid-900.woff2,fa-solid-900.woff2,aa75998623a391e61c6901794ace832e3ecdd288b56d608f21bea0411acc0b8e"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-regular-400.woff2,fa-regular-400.woff2,e3456d1283b9d75337a773dfd147bf908fd02c01b4bf48576d8603a69b13cbe5"
  "webfont,https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/webfonts/fa-brands-400.woff2,fa-brands-400.woff2,d7236a19bf23cbb2027280e8f51dc99d6c45976a2ed60de73382b034b18a2b68"

  # Montserrat Font files
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtr6Hw5aXo.woff2,Montserrat-Regular.woff2,ddc148b8a0a27b1449fda6033f4a0defac9bd43210117b50d5d7ad1eda09f394"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCtZ6Hw5aXo.woff2,Montserrat-Medium.woff2,ed121b1a8fbf30998a4ed0a7c8343abe9091ac4744f1c24b602b5d3f962bdb78"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCu173w5aXo.woff2,Montserrat-SemiBold.woff2,98be19bc78b5bc5d419e4fa6ea055ebd4671a963e2cc644aeed4362f15d14c31"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUHjIg1_i6t8kCHKm4532VJOt5-QNFgpCuM73w5aXo.woff2,Montserrat-Bold.woff2,f31b80562610135edd91a86ec7f243c5eeaec2ec08337e6a20c2d135d8e217da"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq6R9WXZ0pg.woff2,Montserrat-Italic.woff2,55ac0fce6af393313fc9be2ff266ea61a91720d74a72209a6d2ca71b546bc565"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq5Z9WXZ0pg.woff2,Montserrat-MediumItalic.woff2,18d22bb0c768dbf707429938d52fe552da2b4367a5b04ba53f9ebfd8d4eb64d1"
  "font,https://fonts.gstatic.com/s/montserrat/v25/JTUFjIg1_i6t8kCHKm459Wx7xQYXK0vOoz6jq3p6WXZ0pg.woff2,Montserrat-SemiBoldItalic.woff2,e7c93612df5114e469ff5d43caa510cbe324f6b0158a919ec2d8ff20256b5c1b"

  # KaTeX fonts. katex.min.css loads them from fonts/ beside it, which
  # vendor_fetch links to vendor/fonts.
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_AMS-Regular.woff2,KaTeX_AMS-Regular.woff2,0cdd387c9590a1a9f9794560022dbb59654a7d86f187aa0c81495ad42d3a7308"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Caligraphic-Bold.woff2,KaTeX_Caligraphic-Bold.woff2,de7701e42cf1f4cf0b766c03fb27977207eee2f4fd5d76fa82188406da43ea4c"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Caligraphic-Regular.woff2,KaTeX_Caligraphic-Regular.woff2,5d53e70ad607c2352162dec9e0923fb54ecdafaccbf604cd8dcf7d00facb989b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Fraktur-Bold.woff2,KaTeX_Fraktur-Bold.woff2,74444efd593c005e3f4573b44524704c0af0a937fe911cca9e94068d0d140d3f"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Fraktur-Regular.woff2,KaTeX_Fraktur-Regular.woff2,51814d270d06ff0255dba0799994fa4d8c84d11f09951d47595f4abb1f3602dc"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Bold.woff2,KaTeX_Main-Bold.woff2,0f60d1b897938ec918c8ce073092411baf9438f6739465693ff18b0f9d20b021"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-BoldItalic.woff2,KaTeX_Main-BoldItalic.woff2,99cd42a3c072d918f2f44984a807cf7aa16e13545fd0875fc07c6c65f99e715b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Italic.woff2,KaTeX_Main-Italic.woff2,97479ca6cce906abc961ecac96faa5f9ca2e61b8e7670d475826bcdee9a7c267"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Main-Regular.woff2,KaTeX_Main-Regular.woff2,c2342cd8b869e01752a9321dc17213fc40d4d04c79688c1d43f2cf316abd7866"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Math-BoldItalic.woff2,KaTeX_Math-BoldItalic.woff2,dc47344dbb6cb5b655c8460d561f4df5f501b90c804ad3c6cec65fe322351ab1"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Math-Italic.woff2,KaTeX_Math-Italic.woff2,7af58c5ec8f132a2ddde9027c6d7814decce4d3b822a11192a42a20e2e973264"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Bold.woff2,KaTeX_SansSerif-Bold.woff2,e99ae51144bf1232efcc1bfe5add36262c6866b0faab24fa75740e1b98577a62"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Italic.woff2,KaTeX_SansSerif-Italic.woff2,00b26ac825e2095056396e0553b8ac26d3f8ad158c3826e28b4c45b385c4714a"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_SansSerif-Regular.woff2,KaTeX_SansSerif-Regular.woff2,68e8c73ef42afd3ccec58bf0fba302cce448938e7fc020a5e31f8a952eee1342"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Script-Regular.woff2,KaTeX_Script-Regular.woff2,036d4e95149b69ff9bcc0cd55771efeb25ffa3947293e69acd78d5ac328c684b"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size1-Regular.woff2,KaTeX_Size1-Regular.woff2,6b47c40166b6dbe21a5dfca7718413f2147fd2399be1ba605d8ad39cedf25dfe"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size2-Regular.woff2,KaTeX_Size2-Regular.woff2,d04c54219f9eaec6d4d4fd42dfb28785975a4794d6b2fc71e566b9cd6db842dd"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size3-Regular.woff2,KaTeX_Size3-Regular.woff2,73d591271b1604960cb10bb90fee021670af7297017e0e98480b332d11f51995"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Size4-Regular.woff2,KaTeX_Size4-Regular.woff2,a4af7d414440a1c1790825cfb700cf9cf43b0f2c4b04f0ebc523011ad9853ec0"
  "font,https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/fonts/KaTeX_Typewriter-Regular.woff2,KaTeX_Typewriter-Regular.woff2,71d517d67827787cfabdf186914cc3358eda539e37931941f2b2fd4a21f68c0b"
)

# Montserrat CSS template with all font faces
MONTSERRAT_CSS=$(cat <<'EOF'
/* Montserrat Font */
@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 400;
  src: url('/vendor/fonts/Montserrat-Regular.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 500;
  src: url('/vendor/fonts/Montserrat-Medium.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 600;
  src: url('/vendor/fonts/Montserrat-SemiBold.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 700;
  src: url('/vendor/fonts/Montserrat-Bold.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 400;
  src: url('/vendor/fonts/Montserrat-Italic.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 500;
  src: url('/vendor/fonts/Montserrat-MediumItalic.woff2') format('woff2');
}

@font-face {
  font-family: 'Montserrat';
  font-style: italic;
  font-weight: 600;
  src: url('/vendor/fonts/Montserrat-SemiBoldItalic.woff2') format('woff2');
}
EOF
)

vendor_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | cut -d' ' -f1
  else
    shasum -a 256 "$@" | cut -d' ' -f1
  fi
}

# Where a listed file goes, relative to the vendor directory.
vendor_asset_path() {
  case "$1" in
    css) echo "css/$2" ;;
    js) echo "js/$2" ;;
    font) echo "fonts/$2" ;;
    webfont) echo "webfonts/$2" ;;
    pdfjs) echo "pdfjs/$2" ;;
    *) echo "Unknown asset type: $1" >&2; return 1 ;;
  esac
}

# "path<TAB>sha256" for every file vendor_fetch writes, relative to the vendor
# directory. The packaging gates read this instead of parsing the list.
vendor_manifest() {
  local asset type url filename sha rel
  for asset in "${ASSETS[@]}"; do
    IFS=',' read -r type url filename sha <<< "$asset"
    rel=$(vendor_asset_path "$type" "$filename") || return 1
    printf '%s\t%s\n' "$rel" "$sha"
  done
  printf '%s\t%s\n' "css/montserrat.css" "$(printf '%s\n' "$MONTSERRAT_CSS" | vendor_sha256)"
}

# Brings every listed file under the given vendor directory to its pinned
# bytes. A file that already matches is kept, so a build needs no network
# once the files are in place; any other file is downloaded again. A failed
# download or a hash mismatch stops with an error: saving whatever the server
# returned once put an HTML error page where a stylesheet belonged.
vendor_fetch() {
  local dir="$1" asset type url filename sha rel dest got
  for asset in "${ASSETS[@]}"; do
    IFS=',' read -r type url filename sha <<< "$asset"
    rel=$(vendor_asset_path "$type" "$filename") || return 1
    dest="${dir}/${rel}"
    if [ -f "$dest" ] && [ "$(vendor_sha256 "$dest")" = "$sha" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    echo "Downloading: $url"
    if ! curl --fail --location --silent --show-error --retry 2 \
         --connect-timeout 15 --max-time 300 -o "${dest}.download" "$url"; then
      rm -f "${dest}.download"
      echo "Failed to download: $url" >&2
      return 1
    fi
    got=$(vendor_sha256 "${dest}.download")
    if [ "$got" != "$sha" ]; then
      rm -f "${dest}.download"
      echo "Hash mismatch for $url: expected $sha, got $got" >&2
      return 1
    fi
    mv -f "${dest}.download" "$dest"
  done
  # A Windows payload carries the link as a copy of the directory; keep that.
  if [ ! -e "${dir}/css/fonts" ] || [ -L "${dir}/css/fonts" ]; then
    ln -sfn ../fonts "${dir}/css/fonts"
  fi
  printf '%s\n' "$MONTSERRAT_CSS" > "${dir}/css/montserrat.css"
}
