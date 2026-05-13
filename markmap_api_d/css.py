CSS_CODE = r"""<style id="mm-custom-css">

/* Target the foreignObject directly */

#mindmap g[data-depth="1"] foreignObject {

  width: 130px !important;

}

/* Target the inner div */

#mindmap g[data-depth="1"] foreignObject div {

  width: 130px !important;

  max-width: 130px !important;

}

</style>

"""
