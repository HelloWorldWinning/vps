<?php
/**
 * Simple Blog & Diary Theme for Typecho
 * 
 * @package Simple 
 * @author Lin Hai
 * @version 1.0
 * @link https://lhcy.org
 */
if (!defined('__TYPECHO_ROOT_DIR__')) exit;
$this->need('header.php');
?>

<section>
    <div class="container clearfix">
        <div class="main-body">
            <?php while($this->next()): ?>
            <article class="article" itemscope itemtype="http://schema.org/BlogPosting">
                <h2 class="title" itemprop="name headline"><a itemprop="url" href="<?php $this->permalink() ?>"><?php $this->title() ?></a></h2>
                <span class="info"><time datetime="<?php $this->date('c'); ?>" itemprop="datePublished"><?php $this->date(); ?></time></span>
            </article>
            <?php endwhile; ?>
            <div class="pagebar"><?php $this->pageNav('&laquo;', '&raquo;'); ?></div>
        </div>
    </div>
</section>

<?php $this->need('footer.php'); ?>
